// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./AdminRoleUpgrade.sol";
import "./interfaces/IXMTStake.sol";
import "./libraries/CSTDateTime.sol";

contract XMTDividendTransactionFee is AdminRoleUpgrade, Initializable {

    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using CSTDateTime for *;

    address public xmtToken;
    address public treasury;

    function initialize() public initializer {
        _addAdmin(msg.sender);
    }

    mapping(uint256 => uint256) public incomeByTokenAndDay;

    event IncomeRecorded(uint256 indexed dayStart, uint256 amount, uint256 dayTotal);

    function setAboutAddress(address _xmtToken, address _treasury) external onlyAdmin {
        require(_xmtToken != address(0), "token zero");
        require(_treasury != address(0), "treasury zero");
        xmtToken = _xmtToken;
        treasury = _treasury;
    }

    function collectIncome(uint256 amount) external onlyAdmin {
        require(xmtToken != address(0), "xmt token not set");
        require(amount > 0, "amount zero");
        uint256 dayStart = CSTDateTime.today();
        uint256 newTotal = incomeByTokenAndDay[dayStart].add(amount);
        incomeByTokenAndDay[dayStart] = newTotal;
        emit IncomeRecorded(dayStart, amount, newTotal);
    }

    function getDividendByDay() external view returns (uint256) {
        return getAverageDividendLast15Days(CSTDateTime.yesterday());
    }

    function getAverageDividendLast15Days(uint256 dayStartTimestamp) public view returns (uint256) {
        uint256 total = 0;
        uint256 SECONDS_PER_DAY = 86400;
        for (uint256 i = 0; i < 15; i++) {
            uint256 dayStart = dayStartTimestamp - (i * SECONDS_PER_DAY);
            total = total.add(incomeByTokenAndDay[dayStart]);
        }
        return total / 15;
    }

    function getIncomesByDays(uint256[] calldata dayStarts) external view returns (uint256[] memory amounts) {
        amounts = new uint256[](dayStarts.length);
        for (uint256 i = 0; i < dayStarts.length; i++) {
            amounts[i] = incomeByTokenAndDay[dayStarts[i]];
        }
    }
}