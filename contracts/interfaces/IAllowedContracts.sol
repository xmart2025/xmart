// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IAllowedContracts {

    function canTrade(address account) external view returns (bool);
    function canPoolAndStake(address account) external view returns (bool);
    function unbanBlackAddress(address addr, uint256 level) external;
}