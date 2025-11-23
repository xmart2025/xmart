// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "./AdminRoleUpgrade.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "./libraries/CSTDateTime.sol";
import "./interfaces/IXMTEntryPoint.sol";

interface IXMTTradeQuota {

    function finalizeDay() external;
}

interface IXMTPassBurn {

    function burn(uint256 amount) external;
}

contract XMTPointsVesting is AdminRoleUpgrade, Initializable {

    using ECDSA for bytes32;

    enum Rule {D10, D20, D30, D45, D90}

    struct Pct {
        uint256 releasePct;
        uint256 burnPct;
        uint256 daysDuration;
    }

    struct Vesting {
        uint256 totalAmount;
        uint256 claimed;
        uint256 burnAmount;
        uint256 startTime;
        uint256 duration;
        Rule rule;
    }

    address public escdaSigner;
    mapping(uint256 => Pct) public rulePct;
    mapping(uint256 => mapping(uint256 => bool)) public allowed;
    mapping(bytes32 => bool) public usedSignatures;
    mapping(address => Vesting[]) public userVestings;
    mapping(address => uint256[]) public activeIndexes;
    mapping(address => uint256) public nonce;
    mapping(uint256 => bytes32) public merkleRootByDay;
    mapping(uint256 => bool) public merkleUpdated;
    mapping(address => uint256) public releasedTotal;
    IXMTTradeQuota public tradeQuota;
    IXMTEntryPoint public entryPoint;
    address public merkleRootSinger;
    address public passBurn;

    event StarAuthorized(address indexed user, uint256 star);
    event VestingAdded(address indexed user, uint256 ruleIdx, uint256 totalAmount, uint256 burnAmount);
    event Claimed(address indexed user, uint256 amount);
    event DailyMerkleRootUpdated(uint256 indexed day, bytes32 root);
    event DailyVestingDeltaAdded(address indexed user, uint256 indexed day, uint256 amount, uint256 newReleasedTotal);

    function initialize() public initializer {
        _addAdmin(msg.sender);
        initPct();
    }

    function setAboutAddress(address _entryPoint, address quota, address _passBurn) external onlyAdmin {
        entryPoint = IXMTEntryPoint(_entryPoint);
        tradeQuota = IXMTTradeQuota(quota);
        passBurn = _passBurn;
    }

    function setEscdaSigner(address newSigner, address _merkleRootSinger) external onlyAdmin {
        require(newSigner != address(0), "zero");
        escdaSigner = newSigner;
        merkleRootSinger = _merkleRootSinger;
    }

    function updateDailyMerkleRoot(bytes32 newRoot) external  {
        require(newRoot != bytes32(0), "zero root");
        require(msg.sender == merkleRootSinger, "not merkleRootSinger");
        require(address(tradeQuota) != address(0), "tradeQuota not set");
        uint256 day = CSTDateTime.today();
        require(!merkleUpdated[day], "already updated");
        merkleRootByDay[day] = newRoot;
        merkleUpdated[day] = true;
        emit DailyMerkleRootUpdated(day, newRoot);
        tradeQuota.finalizeDay();
    }

    function addVesting(

        uint256 totalAmount_,
        bytes32[] calldata merkleProof,
        uint256 ruleIdx,
        uint256 star,
        uint256 blockNumber,
        bytes calldata signature
    ) external {
        require(ruleIdx <= uint256(Rule.D90), "rule err");
        require(star <= 8, "star err");
        require(allowed[star][ruleIdx], "not allowed");
        uint256 day = CSTDateTime.today();
        require(merkleUpdated[day], "merkle not updated");
        uint256 yesterday = CSTDateTime.yesterday();
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, yesterday, totalAmount_));
        bytes32 root = merkleRootByDay[day];
        require(MerkleProof.verify(merkleProof, root, leaf), "invalid proof");
        require(block.number >= blockNumber && block.number - blockNumber <= 200, "expired");
        uint256 currentNonce = nonce[msg.sender];
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "XmtPointsVesting:addVesting",
                msg.sender,
                totalAmount_,
                ruleIdx,
                star,
                day,
                currentNonce,
                blockNumber,
                address(this),
                block.chainid
            )
        );
        bytes32 ethSigned = messageHash.toEthSignedMessageHash();
        require(ECDSA.recover(ethSigned, signature) == escdaSigner, "invalid signature");
        require(!usedSignatures[ethSigned], "sig used");
        usedSignatures[ethSigned] = true;
        uint256 prevReleased = releasedTotal[msg.sender];
        require(totalAmount_ >= prevReleased, "total < released");
        uint256 delta = totalAmount_ - prevReleased;
        require(delta > 0, "nothing to release");
        Pct memory pct = rulePct[ruleIdx];
        uint256 burnAmount = (delta * pct.burnPct) / 100;
        uint256 releasableAmount = delta - burnAmount;
        if (burnAmount > 0 && passBurn != address(0)) {
            IXMTPassBurn(passBurn).burn(burnAmount);
        }
        Vesting memory v = Vesting({
            totalAmount: releasableAmount,
            claimed: 0,
            burnAmount: burnAmount,
            startTime: block.timestamp,
            duration: pct.daysDuration * 1 days,
            rule: Rule(ruleIdx)
        });
        userVestings[msg.sender].push(v);
        uint256 index = userVestings[msg.sender].length - 1;
        activeIndexes[msg.sender].push(index);
        releasedTotal[msg.sender] = totalAmount_;
        nonce[msg.sender] = currentNonce + 1;
        emit DailyVestingDeltaAdded(msg.sender, day, delta, totalAmount_);
        emit VestingAdded(msg.sender, ruleIdx, releasableAmount, burnAmount);
    }

    function verifyMerkleProof(

        address account,
        bytes32[] calldata merkleProof,
        uint256 totalAmount_
    ) external view returns (bool) {
        uint256 day = CSTDateTime.today();
        uint256 yesterday = CSTDateTime.yesterday();
        bytes32 leaf = keccak256(abi.encodePacked(account, yesterday, totalAmount_));
        bytes32 root = merkleRootByDay[day];
        return MerkleProof.verify(merkleProof, root, leaf);
    }

    function verifySig(

        address account,
        uint256 totalAmount_,
        uint256 ruleIdx,
        uint256 star,
        uint256 day,
        uint256 blockNumber,
        bytes calldata signature
    ) external view returns (bool) {
        if (ruleIdx > uint256(Rule.D90) || star > 8) return false;
        uint256 currentNonce = nonce[account];
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "XmtPointsVesting:addVesting",
                account,
                totalAmount_,
                ruleIdx,
                star,
                day,
                currentNonce,
                blockNumber,
                address(this),
                block.chainid
            )
        );
        bytes32 ethSigned = messageHash.toEthSignedMessageHash();
        return ECDSA.recover(ethSigned, signature) == escdaSigner;
    }

    function claimAll() external {
        Vesting[] storage vestings = userVestings[msg.sender];
        uint256[] storage indexes = activeIndexes[msg.sender];
        uint256 totalClaimed = 0;
        uint256 i = 0;
        while (i < indexes.length) {
            uint256 idx = indexes[i];
            Vesting storage v = vestings[idx];
            uint256 claimable = _vested(v);
            if (claimable > v.claimed) {
                uint256 amount = claimable - v.claimed;
                v.claimed = claimable;
                totalClaimed += amount;
            }
            if (v.claimed >= v.totalAmount) {
                indexes[i] = indexes[indexes.length - 1];
                indexes.pop();
            } else {
                i++;
            }
        }
        entryPoint.addAmountWithStatus(msg.sender, totalClaimed, 5);
        require(totalClaimed > 0, "nothing to claim");
        emit Claimed(msg.sender, totalClaimed);
    }

    function _vested(Vesting memory v) internal view returns (uint256) {
        if (block.timestamp <= v.startTime) return 0;
        if (block.timestamp >= v.startTime + v.duration) return v.totalAmount;
        uint256 elapsed = block.timestamp - v.startTime;
        return (v.totalAmount * elapsed) / v.duration;
    }

    function getClaimable(address user) external view returns (uint256) {
        Vesting[] storage vestings = userVestings[user];
        uint256[] storage indexes = activeIndexes[user];
        uint256 totalClaimable = 0;
        for (uint256 i = 0; i < indexes.length; i++) {
            Vesting storage v = vestings[indexes[i]];
            uint256 vested = _vested(v);
            if (vested > v.claimed) {
                totalClaimable += (vested - v.claimed);
            }
        }
        return totalClaimable;
    }

    function getActiveVestings(address user) external view returns (Vesting[] memory) {
        uint256[] storage indexes = activeIndexes[user];
        Vesting[] memory result = new Vesting[](indexes.length);
        for (uint256 i = 0; i < indexes.length; i++) {
            result[i] = userVestings[user][indexes[i]];
        }
        return result;
    }

    function getAllVestings(address user) external view returns (Vesting[] memory) {
        return userVestings[user];
    }

    function initPct() internal {
        rulePct[uint8(Rule.D10)] = Pct({releasePct: 60, burnPct: 40, daysDuration: 10});
        rulePct[uint8(Rule.D20)] = Pct({releasePct: 65, burnPct: 35, daysDuration: 20});
        rulePct[uint8(Rule.D30)] = Pct({releasePct: 70, burnPct: 30, daysDuration: 30});
        rulePct[uint8(Rule.D45)] = Pct({releasePct: 80, burnPct: 20, daysDuration: 45});
        rulePct[uint8(Rule.D90)] = Pct({releasePct: 100, burnPct: 0, daysDuration: 90});
        allowed[0][uint8(Rule.D45)] = true;
        allowed[0][uint8(Rule.D90)] = true;
        allowed[1][uint8(Rule.D30)] = true;
        allowed[1][uint8(Rule.D45)] = true;
        allowed[1][uint8(Rule.D90)] = true;
        allowed[2][uint8(Rule.D30)] = true;
        allowed[2][uint8(Rule.D45)] = true;
        allowed[2][uint8(Rule.D90)] = true;
        allowed[3][uint8(Rule.D20)] = true;
        allowed[3][uint8(Rule.D30)] = true;
        allowed[3][uint8(Rule.D45)] = true;
        allowed[3][uint8(Rule.D90)] = true;
        allowed[4][uint8(Rule.D20)] = true;
        allowed[4][uint8(Rule.D30)] = true;
        allowed[4][uint8(Rule.D45)] = true;
        allowed[4][uint8(Rule.D90)] = true;
        for (uint8 s = 5; s <= 8; s++) {
            allowed[s][uint8(Rule.D10)] = true;
            allowed[s][uint8(Rule.D20)] = true;
            allowed[s][uint8(Rule.D30)] = true;
            allowed[s][uint8(Rule.D45)] = true;
            allowed[s][uint8(Rule.D90)] = true;
        }
    }
}