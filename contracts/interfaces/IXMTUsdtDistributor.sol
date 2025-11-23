// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IXMTUsdtDistributor {
    enum SourceType {
        Default,
        Entry,
        Trade
    }

    function distribute(address addr, uint256 usdtAmount, SourceType source) external returns (uint256);
}