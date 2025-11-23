// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./AdminRoleUpgrade.sol";
import "./interfaces/IXMTStake.sol";
import "./libraries/CSTDateTime.sol";

contract XMTCityNodeFee is AdminRoleUpgrade, Initializable {

    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using CSTDateTime for *;

    function initialize() public initializer {
        _addAdmin(msg.sender);
    }

    mapping(uint256 => uint256) public incomeByTokenAndDay;

    event IncomeRecorded(uint256 indexed dayStart, uint256 amount, uint256 dayTotal);

    function collectIncome(uint256 amount) external onlyAdmin {
        require(amount > 0, "amount zero");
        uint256 dayStart = CSTDateTime.today();
        uint256 newTotal = incomeByTokenAndDay[dayStart].add(amount);
        incomeByTokenAndDay[dayStart] = newTotal;
        emit IncomeRecorded(dayStart, amount, newTotal);
    }

    function getCityNodeFeeByDay() external view returns (uint256) {
        return incomeByTokenAndDay[CSTDateTime.yesterday()];
    }

    function getCityNodeFeesByDays(uint256[] calldata dayStarts) external view returns (uint256[] memory amounts) {
        amounts = new uint256[](dayStarts.length);
        for (uint256 i = 0; i < dayStarts.length; i++) {
            amounts[i] = incomeByTokenAndDay[dayStarts[i]];
        }
    }
}