// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "./libraries/CSTDateTime.sol";
import "./AdminRoleUpgrade.sol";
import "./interfaces/IXMTEntryPoint.sol";
import "./interfaces/IXMTLiquidityManager.sol";

contract XMTTradeQuota is AdminRoleUpgrade, Initializable{

    struct DayStats {
        uint256 totalBidPriceVolume;
        uint256 totalDexPriceVolume;
        uint256 totalVolume;
        int256 priceIncreaseRate;
        uint256 dailyQuota;
        bool finalized;
    }

    mapping(uint256 => DayStats) public dayStats;
    mapping(uint256 => uint256) public lastDayC2CVolume;
    mapping(uint256 => uint256) public lastDayOTCVolume;
    uint256 public constant MAX_RATE = 100_000;
    IXMTEntryPoint public entryPoint;
    IXMTLiquidityManager public liquidityManager;

    function initialize() public initializer {
        _addAdmin(msg.sender);
    }

    function setAboutAddress(address _entryPoint, address _liquidityManager) external onlyAdmin {
        entryPoint = IXMTEntryPoint(_entryPoint);
        liquidityManager = IXMTLiquidityManager(_liquidityManager);
    }

    function recordTrade(uint256 bidPrice, uint256 dexPrice, uint256 volume) external onlyAdmin {
        require(volume > 0, "Invalid volume");
        uint256 today = CSTDateTime.today();
        DayStats storage ds = dayStats[today];
        ds.totalBidPriceVolume += bidPrice * volume;
        ds.totalDexPriceVolume += dexPrice * volume;
        ds.totalVolume += volume;
    }

    function updateC2CVolume(uint256 c2c) external onlyAdmin {
        lastDayC2CVolume[CSTDateTime.today()] += c2c;
    }

    function updateOTCVolume(uint256 otc) external onlyAdmin {
        lastDayOTCVolume[CSTDateTime.today()] += otc;
    }

    function finalizeDay() external {
        DayStats storage ds = dayStats[CSTDateTime.yesterday()];
        if (ds.finalized) return;
        if (ds.totalVolume > 0) {
            uint256 avgBid = ds.totalBidPriceVolume / ds.totalVolume;
            uint256 avgDex = ds.totalDexPriceVolume / ds.totalVolume;
            int256 diff = int256(avgBid) - int256(avgDex);
            int256 rate = (diff * 1_000_000) / int256(avgDex);
            if (rate > int256(MAX_RATE)) rate = int256(MAX_RATE);
            if (rate < -int256(MAX_RATE)) rate = -int256(MAX_RATE);
            ds.priceIncreaseRate = rate;
        } else {
            ds.priceIncreaseRate = 0;
        }
        if (ds.priceIncreaseRate <= 0) {
            ds.dailyQuota = 0;
        } else {
            uint256 baseVolume = lastDayC2CVolume[CSTDateTime.yesterday()] + lastDayOTCVolume[CSTDateTime.yesterday()];
            ds.dailyQuota = (baseVolume * 10 / 100) * uint256(ds.priceIncreaseRate) / 1_000_000;
        }
        liquidityManager.updateBasePrice(int256(ds.priceIncreaseRate));
        entryPoint.updateQuota(ds.dailyQuota);
        ds.finalized = true;
    }

    function getTodayInfo() external view returns (int256 rate, uint256 quota) {
        uint256 today = CSTDateTime.today();
        DayStats storage ds = dayStats[today];
        return (ds.priceIncreaseRate, ds.dailyQuota);
    }

    function getYesterdayInfo() external view returns (int256 rate, uint256 quota) {
        uint256 yesterday = CSTDateTime.yesterday();
        DayStats storage ds = dayStats[yesterday];
        return (ds.priceIncreaseRate, ds.dailyQuota);
    }

    function getDayStatsByTimestamp(uint256 timestamp) external view returns (
        uint256 totalBidPriceVolume,
        uint256 totalDexPriceVolume,
        uint256 totalVolume,
        int256 priceIncreaseRate,
        uint256 dailyQuota,
        bool finalized
    ) {
        DayStats storage stats = dayStats[timestamp];
        return (
            stats.totalBidPriceVolume,
            stats.totalDexPriceVolume,
            stats.totalVolume,
            stats.priceIncreaseRate,
            stats.dailyQuota,
            stats.finalized
        );
    }
}