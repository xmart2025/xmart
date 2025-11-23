// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IRelation {

    function Inviter(address user) external view returns (address);
    function invListLength(address addr_) external view returns (uint256);
}