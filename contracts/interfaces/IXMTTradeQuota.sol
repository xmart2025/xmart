// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IXMTTradeQuota {

    function recordTrade(uint256 bidPrice, uint256 dexPrice, uint256 volume) external;
    function updateC2CVolume(uint256 c2c) external;
    function updateOTCVolume(uint256 otc) external;
    function finalizeDay() external;
    function getTodayInfo() external view returns (int256 rate, uint256 quota);
    function getYesterdayInfo() external view returns (int256 rate, uint256 quota);
    function getDayStatsByTimestamp(uint256 timestamp) external view returns (
        uint256 totalBidPriceVolume,
        uint256 totalDexPriceVolume,
        uint256 totalVolume,
        int256 priceIncreaseRate,
        uint256 dailyQuota,
        bool finalized
    );
}