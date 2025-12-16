// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./AdminRoleUpgrade.sol";
import "./interfaces/IXMTStake.sol";
import "./interfaces/IXMTEntryPoint.sol";
import "./interfaces/IXMTpassPointsPool.sol";
import "./interfaces/IAllowedContracts.sol";
import "./interfaces/IXMTClubTraderManage.sol";

contract XMTPool is AdminRoleUpgrade, Initializable {

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    IXMTStake public stake;
    IXMTEntryPoint public entryPoint;

    struct NodeInfo {
        uint16 day;
        uint16 apr;
        uint256 nodeId;
        uint256 price;
    }

    struct UserState {
        bool initialized;
        uint64 activeUntil;
        uint256 lastNodeId;
    }

    mapping(address => mapping(uint256 => UserState)) public userStates;
    mapping(address => mapping(uint256 => uint256)) public userNodePurchaseCount;
    mapping(address => mapping(uint256 => uint256)) public userMachinePurchaseCount;
    mapping(address => mapping(uint256 => mapping(uint16 => uint256))) public userCyclePurchaseCount;
    mapping(uint256 => NodeInfo) private _nodes;
    mapping(address => mapping(uint256 => bool)) public machineIdStatus;
    uint16 public day1Duration;
    uint16 public day2Duration;
    uint16 public day3Duration;
    uint16 public day4Duration;
    IXMTpassPointsPool public pointsPool;
    IAllowedContracts public allowedContracts;
    IXMTClubTraderManage public traderManager;

    event Purchased(
        address indexed user,
        uint256 indexed machineId,
        uint256 indexed nodeId,
        uint16 day,
        uint256 price,
        uint16 apr,
        uint64 startTime,
        uint64 endTime
    );

    event MachinePurchasedCount(address indexed user, uint256 indexed machineId, uint256 totalCount);
    event NodeSet(uint256 indexed nodeId, uint256 price, uint16 day, uint16 apr);
    event CompoundingTaxCharged(
        address indexed user,
        uint256 indexed machineId,
        uint16 day,
        uint256 nodeId,
        uint256 taxRateBps,
        uint256 taxAmount
    );

    function initialize() public initializer {
        _addAdmin(msg.sender);
    }

    function setAboutAddress(address _stakeAddr, address _entryPoint, address _pointsPool, address _allowedContractsAddr, address _traderManager) external onlyAdmin {
        stake = IXMTStake(_stakeAddr);
        entryPoint = IXMTEntryPoint(_entryPoint);
        pointsPool = IXMTpassPointsPool(_pointsPool);
        allowedContracts = IAllowedContracts(_allowedContractsAddr);
        traderManager = IXMTClubTraderManage(_traderManager);
    }

    function buy(uint256 machineId, uint256 nodeId) external {
        require(allowedContracts.canPoolAndStake(msg.sender), "not pool and stake");
        if (address(traderManager) != address(0)) {
            require(!traderManager.isTrader(msg.sender), "trader banned");
        }
        require(!machineIdStatus[msg.sender][machineId], "Has purchased");
        UserState storage st = userStates[msg.sender][machineId];
        NodeInfo storage n = _nodes[nodeId];
        require(n.nodeId != 0, "node not found");
        require(_inAllowedSet(machineId, nodeId), "node not allowed for machine");
        _assertNextNodeAllowed(machineId, st.lastNodeId, nodeId);
        entryPoint.processQueue(100);
        uint64 actualDays = uint64(n.day);
        uint16 dayKey = uint16(actualDays);
        uint256 priorCount = userCyclePurchaseCount[msg.sender][machineId][dayKey];
        uint256 taxBps = priorCount * 500;
        if (taxBps > 1500) {
            taxBps = 1500;
        }

        // uint256 dailyProfit = n.price.mul(n.apr).div(10000);
        // uint256 totalProfit = dailyProfit.mul(uint256(actualDays));
        // uint256 taxAmount = totalProfit.mul(taxBps).div(10000);
        // 复利税改为按本金计提
        uint256 taxAmount = n.price.mul(taxBps).div(10000);
        _collectPayment(msg.sender, n.price);
        if (taxAmount > 0) {
            entryPoint.subAmountWithStatus(msg.sender, taxAmount, 9);
            emit CompoundingTaxCharged(msg.sender, machineId, dayKey, nodeId, taxBps, taxAmount);
        }
        st.initialized = true;
        st.lastNodeId = nodeId;
        uint64 start = uint64(block.timestamp);
        uint64 end = start + uint64(actualDays) * 1 days;
        st.activeUntil = end;
        userNodePurchaseCount[msg.sender][nodeId] += 1;
        userMachinePurchaseCount[msg.sender][machineId] += 1;
        userCyclePurchaseCount[msg.sender][machineId][dayKey] += 1;
        machineIdStatus[msg.sender][machineId] = true;
        stake.addStakePackage(msg.sender, machineId, nodeId, n.day, n.price.div(10), false);
        emit Purchased(msg.sender, machineId, nodeId, n.day, n.price, n.apr, start, end);
    }

    function _collectPayment(address user, uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        uint256 remaining = amount;
        if (address(pointsPool) != address(0)) {
            uint256 availablePoints = pointsPool.userPointsReceived(user);
            if (availablePoints > 0) {
                uint256 usedPoints = availablePoints >= remaining ? remaining : availablePoints;
                pointsPool.spendPoints(user, usedPoints);
                remaining -= usedPoints;
            } 
        }
        if (remaining > 0) {
            entryPoint.subAmountWithStatus(user, remaining, 1);
        }
    }

    function updateMachineIdStatus(address user,uint256 machineId) external onlyAdmin{
        machineIdStatus[user][machineId] = false;
    }

    function getNodeDetail(uint256 nodeId) external view returns (
        uint256 nodeIdEcho,
        uint256 price,
        uint256 day,
        uint256 apr
    ) {
        NodeInfo storage n = _nodes[nodeId];
        require(n.nodeId != 0, "node not found");
        return (n.nodeId, n.price, uint256(n.day), uint256(n.apr));
    }

    function getNode(uint256 nodeId) external view returns (uint16 day, uint16 apr, uint256 price) {
        NodeInfo storage n = _nodes[nodeId];
        require(n.nodeId != 0, "node not found");
        return (n.day, n.apr, n.price);
    }

    function getUserCompoundingTax(address user, uint256 machineId, uint256 nodeId) external view returns (uint256 taxAmount, uint256 taxBps) {
        NodeInfo storage n = _nodes[nodeId];
        require(n.nodeId != 0, "node not found");
        uint16 dayKey = n.day;
        uint256 priorCount = userCyclePurchaseCount[user][machineId][dayKey];
        taxBps = priorCount * 500;
        if (taxBps > 1500) {
            taxBps = 1500;
        }
        taxAmount = n.price.mul(taxBps).div(10000);
        return (taxAmount, taxBps);
    }

    function getLastPurchaseInfo(address user, uint256 machineId) external view returns (uint256 lastNodeId, uint16 day, uint16 apr, uint256 price) {
        UserState storage st = userStates[user][machineId];
        lastNodeId = st.lastNodeId;
        if (lastNodeId == 0) {
            return (0, 0, 0, 0);
        }
        NodeInfo storage n = _nodes[lastNodeId];
        require(n.nodeId != 0, "node not found");
        return (lastNodeId, n.day, n.apr, n.price);
    }

    function adminSetNodeBatch(
        uint256[] calldata ids,
        uint256[] calldata prices,
        uint16[] calldata days_,
        uint16[] calldata aprs
    ) external onlyAdmin {
        uint256 len = ids.length;
        require(prices.length == len && days_.length == len && aprs.length == len, "length mismatch");
        for (uint256 i = 0; i < len; i++) {
            _nodes[ids[i]] = NodeInfo({
                day: days_[i],
                apr: aprs[i],
                nodeId: ids[i],
                price: prices[i]
            });
            emit NodeSet(ids[i], prices[i], days_[i], aprs[i]);
        }
    }

    function _assertNextNodeAllowed(uint256 machineId, uint256 lastNodeId, uint256 nextNodeId) internal pure {
        require(_samePriceBucket(machineId, nextNodeId), "node not in price bucket");
        uint256 nextSuffix = nextNodeId % 100;
        if (lastNodeId == 0) {
            require(nextSuffix == 1, "first buy must be 30d");
        } else {
            uint256 lastSuffix = lastNodeId % 100;
            require(nextSuffix == lastSuffix + 1 || nextSuffix == lastSuffix, "must buy next period in order");
        }
    }

    function _isFirst30(uint256 machineId, uint256 nodeId) internal pure returns (bool) {
        return (nodeId / 100) == (machineId / 100) && (nodeId % 100) == 1;
    }

    function _samePriceBucket(uint256 machineId, uint256 nodeId) internal pure returns (bool) {
        return (nodeId / 100) == (machineId / 100);
    }

    function _inAllowedSet(uint256 machineId, uint256 nodeId) internal pure returns (bool) {
        if ((nodeId / 100) != (machineId / 100)) return false;
        uint256 suffix = nodeId % 100;
        return suffix >= 1 && suffix <= 4;
    }

    function giveNodeToUser(address user, uint256 nodeId) external onlyAdmin {

        uint256 giftMachineId = 10000;
        NodeInfo storage n = _nodes[nodeId];
        require(n.nodeId != 0, "node not found");
        stake.addStakePackage(user, giftMachineId, nodeId, n.day, n.price.div(10), false);
        uint64 start = uint64(block.timestamp);
        uint64 end = start + uint64(n.day) * 1 days;
        emit Purchased(user, giftMachineId, nodeId, n.day, n.price, n.apr, start, end);
    }

    function clearUserDataBatch(address[] memory users) external onlyAdmin {
        uint256[] memory nodeIds = new uint256[](6);
        nodeIds[0] = 101;
        nodeIds[1] = 201;
        nodeIds[2] = 301;
        nodeIds[3] = 401;
        nodeIds[4] = 501;
        nodeIds[5] = 601;
        uint256[] memory machineIds = new uint256[](17);
        uint256 idx = 0;
        for (uint256 i = 101; i <= 108; i++) {
            machineIds[idx++] = i;
        }
        for (uint256 i = 201; i <= 204; i++) {
            machineIds[idx++] = i;
        }
        machineIds[idx++] = 301;
        for (uint256 i = 401; i <= 402; i++) {
            machineIds[idx++] = i;
        }
        machineIds[idx++] = 501;
        machineIds[idx++] = 601;
        for (uint256 u = 0; u < users.length; u++) {
            address user = users[u];
            for (uint256 m = 0; m < machineIds.length; m++) {
                delete userStates[user][machineIds[m]];
            }
            for (uint256 n = 0; n < nodeIds.length; n++) {
                delete userNodePurchaseCount[user][nodeIds[n]];
            }
            for (uint256 m = 0; m < machineIds.length; m++) {
                delete userMachinePurchaseCount[user][machineIds[m]];
            }
            for (uint256 m = 0; m < machineIds.length; m++) {
                uint256 machineId = machineIds[m];
                for (uint256 n = 0; n < nodeIds.length; n++) {
                    uint256 nodeId = nodeIds[n];
                    if ((nodeId / 100) == (machineId / 100)) {
                        NodeInfo storage node = _nodes[nodeId];
                        if (node.nodeId != 0) {
                            uint16 dayKey = node.day;
                            delete userCyclePurchaseCount[user][machineId][dayKey];
                        }
                    }
                }
            }
            for (uint256 m = 0; m < machineIds.length; m++) {
                delete machineIdStatus[user][machineIds[m]];
            }
        }
    }
}