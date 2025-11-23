// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "./AdminRoleUpgrade.sol";
import "./interfaces/IXMTPool.sol";
import "./interfaces/IXMTStake.sol";
import "./interfaces/IXMTDividendTransactionFee.sol";
import "./interfaces/IXMTTreasury.sol";
import "./interfaces/IXMTpassVesting180Simple.sol";
import "./libraries/CSTDateTime.sol";

contract XMTStarAchiever is AdminRoleUpgrade, Initializable {

    using SafeMathUpgradeable for uint256;
    using ECDSAUpgradeable for bytes32;

    address public rewardSigner;
    IXMTStake public stake;
    IXMTPool public pool;
    mapping(address => uint256) private userClaimXmtmap;
    mapping(address => uint256) public nonce;

    event StarClaimed(address indexed user, uint8 indexed star, uint256 nodeId, uint256 count);
    event StarsBatchClaimed(address indexed user, uint8 indexed upToStar, uint256 totalNodes);

    function initialize() public initializer {
        _addAdmin(msg.sender);
    }

    function setRewardSigner(address _signer) external onlyAdmin {
        require(_signer != address(0), "signer=0");
        rewardSigner = _signer;
    }

    function setExternalContracts(address _stake, address _pool) external onlyAdmin {
        require(_stake != address(0) && _pool != address(0), "addr=0");
        stake = IXMTStake(_stake);
        pool = IXMTPool(_pool);
    }

    function hasClaimed(address user, uint8 star) public view returns (bool) {
        require(star >= 1 && star <= 8, "star invalid");
        uint256 mask = uint256(1) << (star - 1);
        return (userClaimXmtmap[user] & mask) != 0;
    }

    function getClaimedStars(address user) external view returns (bool[8] memory claimed) {
        uint256 bm = userClaimXmtmap[user];
        for (uint8 i = 1; i <= 8; i++) {
            claimed[i - 1] = (bm & (uint256(1) << (i - 1))) != 0;
        }
    }

    function requiredOwnerWeight(uint8 star) public pure returns (uint256) {
        require(star >= 1 && star <= 8, "star invalid");
        if (star == 1) return 10 * 1e18;
        if (star == 2) return 40 * 1e18;
        if (star == 3) return 100 * 1e18;
        if (star == 4) return 600 * 1e18;
        if (star == 5) return 600 * 1e18;
        if (star == 6) return 1600 * 1e18;
        if (star == 7) return 4000 * 1e18;
        return 10000 * 1e18;
    }

    function nodeIdOf(uint8 star) public pure returns (uint256) {
        require(star >= 1 && star <= 8, "star invalid");
        return uint256(star) * 100 + 1;
    }

    function rewardCountOf(uint8 star) public pure returns (uint256) {
        require(star >= 1 && star <= 8, "star invalid");
        return star == 1 ? 2 : 1;
    }

    function claimStar(uint8 star, uint256 signedBlock, bytes calldata signature) external {
        require(false, "error");
        _verifySignature(msg.sender, star, signedBlock, signature);
        _claimForStar(msg.sender, star);
    }

    function claimUpToStar(uint8 upToStar, uint256 signedBlock, bytes calldata signature) external {
        require(false, "error");
        _verifySignature(msg.sender, upToStar, signedBlock, signature);
        uint8 maxStar = upToStar;
        uint256 totalNodes;
        for (uint8 s = 1; s <= maxStar; s++) {
            if (!hasClaimed(msg.sender, s)) {
                totalNodes = totalNodes.add(_claimForStar(msg.sender, s));
            }
        }
        emit StarsBatchClaimed(msg.sender, upToStar, totalNodes);
    }

    function _verifySignature(address user, uint8 star, uint256 signedBlock, bytes calldata signature) internal {
        require(rewardSigner != address(0), "signer unset");
        require(block.number >= signedBlock, "signature future");
        require(block.number - signedBlock <= 200, "signature expired");
        require(star >= 1 && star <= 8, "star invalid");
        require(verifySig(user, star, signedBlock, signature) == rewardSigner, "bad signature");
        nonce[user] = nonce[user].add(1);
    }

    function verifySig(

        address sender,
        uint8 star,
        uint256 blockNumber,
        bytes calldata signature
    ) public view returns(address)  {
        bytes32 messageHash = keccak256(
            abi.encodePacked(sender, star, blockNumber, nonce[sender])
        );
        return (messageHash.toEthSignedMessageHash().recover(signature));
    }

    function verifySig2(

        address sender,
        uint8 star,
        uint256 blockNumber,
        bytes calldata signature
    ) public view returns(address, uint256, uint256, uint256)  {
        bytes32 messageHash = keccak256(
            abi.encode(sender, star, blockNumber, nonce[sender])
        );
        return (messageHash.toEthSignedMessageHash().recover(signature), block.number, nonce[sender], star);
    }

    function _claimForStar(address user, uint8 star) internal returns (uint256 added) {
        require(!hasClaimed(user, star), "already claimed");
        uint256 userWeight = stake.ownerWeight(user);
        require(userWeight >= requiredOwnerWeight(star), "insufficient ownerWeight");
        uint256 nodeId = nodeIdOf(star);
        ( , uint256 price, uint256 day, ) = pool.getNodeDetail(nodeId);
        uint256 singleWeight = price.div(10);
        uint256 count = rewardCountOf(star);
        for (uint256 i = 0; i < count; i++) {
            stake.addStakePackage(user, 0, nodeId, day, singleWeight, true);
        }
        _markClaimed(user, star);
        emit StarClaimed(user, star, nodeId, count);
        return count;
    }

    function _markClaimed(address user, uint8 star) internal {

        uint256 mask = uint256(1) << (star - 1);
        userClaimXmtmap[user] = userClaimXmtmap[user] | mask;
    }
}