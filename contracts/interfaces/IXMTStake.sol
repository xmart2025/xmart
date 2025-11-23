// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IXMTStake {

    function addStakePackage(address _addr, uint256 machineId, uint256 nodeId, uint256 times, uint256 _weight, bool isReward) external;
    function getMiningIds(address _addr) external view returns (uint256[] memory);
    function pledgeTypeId(address user, uint256 miningIndex) external view returns (uint256);
    function unusedTimes(address user, uint256 miningIndex) external view returns (uint256);
    function childCountByDay(address user, uint256 dayTs) external view returns (uint256);
    function getTodayTimestamp() external view returns (uint256);
    function ownerWeight(address user) external view returns (uint256);
    function getActiveDirectCount(address user) external view returns (uint256);
    function getGiftMachineMiningDetails(address user)
        external
        view
        returns (
            uint256[] memory nodeIds,
            uint256[] memory prices,
            uint256[] memory aprs,
            uint256[] memory totalTimes,
            uint256[] memory remainingTimes,
            bool[] memory rewardFlags,
            uint256[] memory machineIds
        );

    function clearUserDataBatch(address[] memory users) external;
}