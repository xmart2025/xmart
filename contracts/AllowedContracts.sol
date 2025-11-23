// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./AdminRoleUpgrade.sol";
import "./interfaces/IXMTStake.sol";
import "./libraries/CSTDateTime.sol";

contract AllowedContracts is AdminRoleUpgrade, Initializable {
    mapping(address => bool) public blackAddress;
    mapping(address => bool) public isTeamExited;
    mapping(address => uint256) public starLevel;

    function initialize() public initializer {
        _addAdmin(msg.sender);
    }

    function setTeamExited(address[] memory addrs) external onlyAdmin {
        for (uint256 index = 0; index < addrs.length; index++) {
            isTeamExited[addrs[index]] = true;
        }
    }

    function setTeamExitedUnban(address[] memory addrs) external onlyAdmin {
        for (uint256 index = 0; index < addrs.length; index++) {
            isTeamExited[addrs[index]] = false;
        }
    }

    function setStarLevel(address[] memory addrs, uint256[] memory levels) external onlyAdmin {
        require(addrs.length == levels.length, "length mismatch");
        for (uint256 index = 0; index < addrs.length; index++) {
            blackAddress[addrs[index]] = true;
            starLevel[addrs[index]] = levels[index];
        }
    }

    function unbanBlackAddress(address addr, uint256 level) external onlyAdmin {
        if(starLevel[addr] > 0 && level >= starLevel[addr] && blackAddress[addr] == true) {
            blackAddress[addr] = false;
        }
    }

    function canTrade(address account) external view returns (bool) {
        return !blackAddress[account] && !isTeamExited[account];
    }

    function canPoolAndStake(address account) external view returns (bool) {
        return !isTeamExited[account];
    }
}