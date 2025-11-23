// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IXMTPool {

    function getNodeDetail(uint256 nodeId) external view returns (
        uint256 nodeIdEcho,
        uint256 price,
        uint256 day,
        uint256 apr
    );

    function updateMachineIdStatus(address user,uint256 machineId) external;
    function userNodePurchaseCount(address user, uint256 nodeId) external view returns (uint256);
    function giveNodeToUser(address user, uint256 nodeId) external;
    function clearUserDataBatch(address[] memory users) external;
}