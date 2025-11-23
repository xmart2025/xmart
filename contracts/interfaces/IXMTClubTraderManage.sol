// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IXMTClubTraderManage {

    function isTrader(address account) external view returns (bool);
    function traderCreator(address trader) external view returns (address);
    function getCreatorTraders(address creator) external view returns (address[] memory);
    function getCreatorTraderCount(address creator) external view returns (uint256);
}