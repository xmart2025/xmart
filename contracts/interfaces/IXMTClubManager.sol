// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IXMTClubManager {

    function addClubAboutAmountWithSeller(address seller, uint256 xmtAmount, uint256 usdtAmount, uint256 lpAmount, uint256 feeUsdtAmount, uint256 status) external;
    function addClubAboutAmountWithBuyer(address buyer, uint256 xmtAmount, uint256 usdtAmount, uint256 status) external;
    function memberClubOf(address user) external view returns (uint256);
    function clubInfo(uint256 clubId) external view returns (
        address creator,
        uint256 createdAt,
        uint256 memberCount,
        uint256 lpAmount,
        uint256 depositUsdt,
        uint256 withdrawUsdt,
        uint256 depositXmtAmount,
        uint256 withdrawXmtAmount,
        uint256 feeUsdt
    );

    function onlyClubOTC(uint256 clubId) external view returns (bool);
    function clubAllowExternalOTC(uint256 clubId) external view returns (bool);
}