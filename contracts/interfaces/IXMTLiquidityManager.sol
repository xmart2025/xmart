// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IXMTLiquidityManager {

    function getTokenPriceInU() external view returns (uint256 price18);
    function addLiquidityWithU(uint256 uAmountIn, address to) external returns (uint256 liquidityMinted);
    function buyTokenWithU(uint256 uAmountIn, uint256 minTokenOut, address to) external returns (uint256[] memory amounts);
    function buyUWithToken(uint256 tokenAmountIn, uint256 minUOut, address to) external returns (uint256[] memory amounts);
    function addLiquidityFromCaller(uint256 uAmountIn, uint256 maxTokenAmount, address to) external returns (uint256 liquidityMinted, uint256 uUsed, uint256 tokenUsed);
    function updateBasePrice(int256 rate) external;
    function isOpenVirtualPrice() external view returns (bool);
}