// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "./AdminRoleUpgrade.sol";
import "./interfaces/IXMTpassPointsPool.sol";

contract XMTpassAirdrop is AdminRoleUpgrade, Initializable {

    using SafeMathUpgradeable for uint256;

    uint256 private constant DAY = 1 days;
    uint256 private constant P0 = 25;
    uint256 private constant P1 = 30;
    uint256 private constant P2 = 35;
    uint256 private constant P3 = 40;
    uint256 private constant P4 = 50;
    uint256 private constant P5 = 75;
    uint256 private constant P6 = 100;
    IXMTpassPointsPool public pointsPool;

    struct UserInfo {
        uint256 allocationBase;
        uint64  startTime;
        uint64  duration;
        uint256 totalClaimed;
        bool    initialized;
        uint256 totalVestingPoints;
        uint8   vestingType;
    }

    mapping(address => UserInfo) public users;
    mapping(address => uint256) public allocations;

    event Initialized(address indexed user, uint256 allocation, uint64 startTime, uint256 immediateReleased);
    event Claimed(address indexed user, uint256 amount, uint256 cumulativeClaimed);
    event PointsPoolUpdated(address indexed newPool);

    function initialize() public initializer {
        _addAdmin(msg.sender);
    }

    function setAboutAddress(address _pointsPool) external onlyAdmin {
        require(_pointsPool != address(0), "invalid pointsPool");
        pointsPool = IXMTpassPointsPool(_pointsPool);
    }

    function setAllocation(address user, uint256 allocation) external onlyAdmin {
        require(allocation > 0, "invalid allocation");
        allocations[user] = allocation;
    }

    function setAllocationBatch(address[] calldata accounts, uint256[] calldata amounts) external onlyAdmin {
        require(accounts.length == amounts.length, "length mismatch");
        for (uint256 i = 0; i < accounts.length; i++) {
            require(amounts[i] > 0, "invalid allocation");
            allocations[accounts[i]] = amounts[i];
        }
    }

    function releaseSelf(uint256 vestingType_) external {

        address user = msg.sender;
        uint256 allocation = allocations[user];
        releaseSelfInit(user, allocation, vestingType_);
    }

    function releaseSelfInit(address user, uint256 allocation, uint256 vestingType_) internal {
        UserInfo storage info = users[user];
        require(!info.initialized, "already initialized");
        require(allocation > 0, "invalid allocation");
        require(vestingType_ <= 6, "invalid vestingType");
        info.allocationBase = allocation;
        info.startTime = uint64(block.timestamp);
        info.duration = _durationForType(uint8(vestingType_));
        info.initialized = true;
        info.vestingType = uint8(vestingType_);
        info.totalVestingPoints = _finalTotalFor(allocation, uint8(vestingType_));
        uint256 vestedNow = _vestedAmount(info, block.timestamp);
        uint256 toClaim = vestedNow;
        if (toClaim > 0) {
            info.totalClaimed = toClaim;
            pointsPool.receivePoints(user, toClaim, 1);
        }
        emit Initialized(user, allocation, info.startTime, toClaim);
        if (toClaim > 0) {
            emit Claimed(user, toClaim, info.totalClaimed);
        }
    }

    function claim() external {
        _claimFor(msg.sender);
    }

    function _claimFor(address user) internal {
        UserInfo storage info = users[user];
        require(info.initialized, "not initialized");
        uint256 vested = _vestedAmount(info, block.timestamp);
        if (vested <= info.totalClaimed) {
            return;
        }

        uint256 delta = vested.sub(info.totalClaimed);
        info.totalClaimed = vested;
        pointsPool.receivePoints(user, delta, 1);
        emit Claimed(user, delta, info.totalClaimed);
    }

    function _vestedAmount(UserInfo storage info, uint256 currentTime) internal view returns (uint256) {
        if (!info.initialized) return 0;
        uint256 start = uint256(info.startTime);
        uint256 d = uint256(info.duration);
        if (info.vestingType == 0) {
            return info.totalVestingPoints;
        }
        if (currentTime <= start) {
            return 0;
        }
        if (currentTime >= start + d) {
            return info.totalVestingPoints;
        }
        return info.totalVestingPoints.mul(currentTime - start).div(d);
    }

    function _finalPctForType(uint8 vestingType_) internal pure returns (uint256) {
        if (vestingType_ == 0) return P0;
        if (vestingType_ == 1) return P1;
        if (vestingType_ == 2) return P2;
        if (vestingType_ == 3) return P3;
        if (vestingType_ == 4) return P4;
        if (vestingType_ == 5) return P5;
        return P6;
    }

    function _finalTotalFor(uint256 allocationBase, uint8 vestingType_) internal pure returns (uint256) {
        uint256 finalPct = _finalPctForType(vestingType_);
        return allocationBase.mul(finalPct).div(100);
    }

    function _durationForType(uint8 vestingType_) internal pure returns (uint64) {
        if (vestingType_ == 0) return 0;
        if (vestingType_ == 1) return 30 days;
        if (vestingType_ == 2) return 60 days;
        if (vestingType_ == 3) return 90 days;
        if (vestingType_ == 4) return 180 days;
        if (vestingType_ == 5) return 360 days;
        return 720 days;
    }

    function claimable(address user) external view returns (uint256) {
        UserInfo storage info = users[user];
        if (!info.initialized) return 0;
        uint256 vested = _vestedAmount(info, block.timestamp);
        if (vested <= info.totalClaimed) return 0;
        return vested - info.totalClaimed;
    }

    function userInfo(address user) external view returns (
        uint256 allocationBase,
        uint64 startTime,
        uint64 duration,
        uint256 totalClaimed,
        uint256 vested,
        uint256 pending,
        uint8 vestingType_,
        uint256 totalVestingPoints
    ) {
        UserInfo storage info = users[user];
        allocationBase = info.allocationBase;
        startTime = info.startTime;
        duration = info.duration;
        totalClaimed = info.totalClaimed;
        vested = _vestedAmount(info, block.timestamp);
        pending = vested > totalClaimed ? vested - totalClaimed : 0;
        vestingType_ = info.vestingType;
        totalVestingPoints = info.totalVestingPoints;
    }

    function getPoolPoints(address addr) external view returns (uint256) {
        return pointsPool.userPointsReceived(addr);
    }

    function clearUserDataBatch(address[] memory userAddrs) external onlyAdmin {
        for (uint256 i = 0; i < userAddrs.length; i++) {
            delete allocations[userAddrs[i]];
            delete users[userAddrs[i]];
        }
    }
}