// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "./AdminRoleUpgrade.sol";

contract XMTpassPointsPool is AdminRoleUpgrade, Initializable {

    using SafeMathUpgradeable for uint256;

    event PointsReceived(address indexed user, uint256 points, uint256 status);
    event PointsSpent(address indexed user, uint256 points);
    event PointsSpentStatus(address indexed user, uint256 points, uint256 status);

    mapping(address => uint256) public userPointsReceived;

    function initialize() public initializer {
        _addAdmin(msg.sender);
    }

    function receivePoints(address user, uint256 points, uint256 status) external onlyAdmin{
        require(points > 0, "Points must be greater than 0");
        userPointsReceived[user] = userPointsReceived[user].add(points);
        emit PointsReceived(user, points, status);
    }

    function receivePointsBatch(address[] calldata users, uint256[] calldata points) external onlyAdmin {
        require(users.length == points.length, "length mismatch");
        for (uint256 i = 0; i < users.length; i++) {
            require(points[i] > 0, "Points must be greater than 0");
            userPointsReceived[users[i]] = userPointsReceived[users[i]].add(points[i]);
            emit PointsReceived(users[i], points[i], 1);
        }
    }

    function spendPoints(address user, uint256 points) external onlyAdmin {
        require(points > 0, "Points must be > 0");
        uint256 bal = userPointsReceived[user];
        require(bal >= points, "insufficient points");
        userPointsReceived[user] = bal - points;
        emit PointsSpentStatus(user, points, 10000);
    }

    function getUserPointsReceived(address user) external view returns (uint256) {
        return userPointsReceived[user];
    }

    function batchGetUserPointsReceived(address[] calldata users) external view returns (uint256[] memory) {
        uint256[] memory results = new uint256[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            results[i] = userPointsReceived[users[i]];
        }
        return results;
    }

    function clearUserDataBatch(address[] memory users) external onlyAdmin {
        for (uint256 i = 0; i < users.length; i++) {
            userPointsReceived[users[i]] = 0;
        }
    }
}