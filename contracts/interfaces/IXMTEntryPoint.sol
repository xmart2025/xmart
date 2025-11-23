// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IXMTEntryPoint {

    function addAmountWithStatus(address user, uint256 amount, uint256 status) external;
    function subAmountWithStatus(address user, uint256 amount, uint256 status) external;
    function updateQuota(uint256 _totalQuota) external;
    function effectiveFeeBps(address user) external view returns (uint256);
    function processQueue(uint256 maxItems) external;
    function clearUserDataBatch(address[] memory users) external;
}