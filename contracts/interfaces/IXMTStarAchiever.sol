// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IXMTStarAchiever {

    function getUserStar(address user) external view returns (uint256);
}