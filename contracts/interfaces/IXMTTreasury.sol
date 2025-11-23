// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IXMTTreasury {

    function withdraw(address to, uint256 amount) external;
    function getEventLog(address addr, address to, uint256 status, uint256 amount, bool isAdd) external;
}