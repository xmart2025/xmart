// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IXMTpassPointsPool {

    function receivePoints(address user, uint256 points, uint256 status) external;
    function spendPoints(address user, uint256 points) external;
    function userPointsReceived(address user) external view returns (uint256);
    function clearUserDataBatch(address[] memory users) external;
}