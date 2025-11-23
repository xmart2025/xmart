// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library CSTDateTime {
    uint256 internal constant SECONDS_PER_DAY = 86400;
    int256 internal constant UTC_OFFSET = 8 * 3600;

    function today() internal view returns (uint256) {
        uint256 dayID = uint256(int256(block.timestamp) + UTC_OFFSET) / SECONDS_PER_DAY;
        return dayID * SECONDS_PER_DAY - uint256(UTC_OFFSET);
    }

    function yesterday() internal view returns (uint256) {
        return today() - SECONDS_PER_DAY;
    }

    function tomorrow() internal view returns (uint256) {
        return today() + SECONDS_PER_DAY;
    }
}