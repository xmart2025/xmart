// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "./AdminRoleUpgrade.sol";
import "./libraries/CSTDateTime.sol";
import "./interfaces/IXMTEntryPoint.sol";
import "./interfaces/IXMTClubTraderManage.sol";

contract XMTTradePoint is AdminRoleUpgrade, Initializable {

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    event TradeAmountLog(address indexed addr, uint256 status, uint256 amount, bool isAdd, address from);

    mapping(address => uint256) public userAmount;
    mapping(address => mapping(uint256 => uint256)) public dailyTransactionCount;
    address public entryPoint;
    uint256 public constant MAX_AMOUNT_PER_TX = 500 * 1e18;
    uint256 public constant MAX_TX_PER_DAY = 3;
    IXMTClubTraderManage public traderManager;
    
    function initialize() public initializer {
        _addAdmin(msg.sender);
    }

    function setAboutAddress(address _entryPoint, address _traderManager) external onlyAdmin {
        entryPoint = _entryPoint;
        traderManager = IXMTClubTraderManage(_traderManager);
    }

    function receiveWithdraw(address user, uint256 amount) external onlyAdmin {
        require(msg.sender == entryPoint, "only entryPoint");
        userAmount[user] = userAmount[user].add(amount);
        getEventLog(user, 4, amount, true, entryPoint);
    }

    function subAmountWithStatus(address user, uint256 amount, uint256 status) public onlyAdmin{
        require(userAmount[user] >= amount, "amount not enough");
        if (status == 1 || status == 2 || status == 3) {
            require(amount <= MAX_AMOUNT_PER_TX, "Amount exceeds maximum per transaction");
            bool isTrader = traderManager.isTrader(user);
            if (!isTrader) {
                uint256 today = CSTDateTime.today();
                uint256 todayCount = dailyTransactionCount[user][today] + 1;
                require(todayCount <= MAX_TX_PER_DAY, "Maximum transactions per day exceeded");
                dailyTransactionCount[user][today] = todayCount;
            }
        }
        userAmount[user] = userAmount[user].sub(amount);
        getEventLog(user, status, amount, false, msg.sender);
    }

    function addAmountWithStatus(address user, uint256 amount, uint256 status) public onlyAdmin{
        userAmount[user] = userAmount[user].add(amount);
        getEventLog(user, status, amount, true, msg.sender);
    }

    function updateDailyTransactionCount(address user, uint256 count) public onlyAdmin{
        dailyTransactionCount[user][CSTDateTime.today()] = count;
    }

    function getEventLog(address addr, uint256 status, uint256 amount, bool isAdd, address from) internal {
        emit TradeAmountLog(addr, status, amount, isAdd, from);
    }
}