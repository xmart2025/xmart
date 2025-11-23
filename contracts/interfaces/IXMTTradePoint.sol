// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IXMTTradePoint {

    function receiveWithdraw(address user, uint256 amount) external;
    function subAmountWithStatus(address user, uint256 amount, uint256 status) external;
    function addAmountWithStatus(address user, uint256 amount, uint256 status) external;
}