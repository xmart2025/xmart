// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./AdminRoleUpgrade.sol";
import "./interfaces/IXMTLiquidityManager.sol";
import "./interfaces/IXMTUsdtDistributor.sol";
import "./interfaces/IXMTTradePoint.sol";
import "./interfaces/IXMTTreasury.sol";
import "./interfaces/IXMTClubManager.sol";

contract XMTTradeDex is AdminRoleUpgrade, Initializable {

    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable public usdt;
    IERC20Upgradeable public xmt;
    IXMTLiquidityManager public lm;
    address public distributor;
    IXMTTradePoint public tradePoint;
    IXMTTreasury public treasury;
    uint256 public constant FEE_BPS_WITH_ENERGY = 3000;
    uint256 public constant FEE_BPS_NO_ENERGY = 5000;
    uint256 public constant STATUS_DEX = 3;
    mapping(address => uint256) public energyOf;
    address public energyManager;
    IXMTClubManager public clubManager;

    event EnergyAdded(address indexed user, uint256 amountAdded, address indexed from);
    event EnergyConsumed(address indexed user, uint256 amountConsumed, uint256 energyLeft);
    event SoldForU(address indexed user, uint256 xmtIn, uint256 usdtOut, uint256 feeUsdt);

    function initialize() public initializer {
        _addAdmin(msg.sender);
    }

    function setAboutAddress(

        address _usdt,
        address _xmt,
        address _lm,
        address _distributor,
        address _tradePoint,
        address _treasury,
        address _energyManager,
        address _clubManager
    ) external onlyAdmin {
        require(
            _usdt != address(0) &&
            _xmt != address(0) &&
            _lm != address(0) &&
            _distributor != address(0) &&
            _tradePoint != address(0) &&
            _treasury != address(0) &&
            _energyManager != address(0),
            "zero addr"
        );
        usdt = IERC20Upgradeable(_usdt);
        xmt = IERC20Upgradeable(_xmt);
        lm = IXMTLiquidityManager(_lm);
        distributor = _distributor;
        tradePoint = IXMTTradePoint(_tradePoint);
        treasury = IXMTTreasury(_treasury);
        energyManager = _energyManager;
        clubManager = IXMTClubManager(_clubManager);
    }

    function addEnergy(address user, uint256 amount) external onlyAdmin {
        require(msg.sender == energyManager, "only energyManager");
        require(user != address(0) && amount > 0, "param");
        energyOf[user] = energyOf[user].add(amount);
        emit EnergyAdded(user, amount, msg.sender);
    }

    function sellForU(uint256 xmtAmount, uint256 minUOut) external {
        require(false, "not open");
        _requireClubMember(msg.sender);
        require(xmtAmount > 0, "xmt =0");
        tradePoint.subAmountWithStatus(msg.sender, xmtAmount, STATUS_DEX);
        treasury.withdraw(address(this), xmtAmount);
        xmt.safeApprove(address(lm), 0);
        xmt.safeApprove(address(lm), xmtAmount);
        uint256[] memory amounts = lm.buyUWithToken(xmtAmount, minUOut, address(this));
        uint256 usdtOut = amounts[amounts.length - 1];
        require(usdtOut > 0, "u out=0");
        uint256 energyAvail = energyOf[msg.sender];
        uint256 energyToUse = energyAvail > xmtAmount ? xmtAmount : energyAvail;
        if (energyToUse > 0) {
            energyOf[msg.sender] = energyAvail - energyToUse;
            emit EnergyConsumed(msg.sender, energyToUse, energyOf[msg.sender]);
        }

        uint256 weightedFeeBps;
        if (energyToUse == 0) {
            weightedFeeBps = FEE_BPS_NO_ENERGY;
        } else if (energyToUse == xmtAmount) {
            weightedFeeBps = FEE_BPS_WITH_ENERGY;
        } else {
            uint256 numerator = energyToUse.mul(FEE_BPS_WITH_ENERGY).add(xmtAmount.sub(energyToUse).mul(FEE_BPS_NO_ENERGY));
            weightedFeeBps = numerator.div(xmtAmount);
        }

        uint256 feeUsdt = usdtOut.mul(weightedFeeBps).div(10000);
        uint256 lpAmount = 0;
        if (feeUsdt > 0) {
            usdt.safeApprove(distributor, 0);
            usdt.safeApprove(distributor, feeUsdt);
            uint256 lpMinted = IXMTUsdtDistributor(distributor).distribute(msg.sender, feeUsdt, IXMTUsdtDistributor.SourceType.Trade);
            lpAmount = lpMinted;
        }

        uint256 netUsdt = usdtOut - feeUsdt;
        usdt.safeTransfer(msg.sender, netUsdt);
        clubManager.addClubAboutAmountWithSeller(msg.sender, xmtAmount, netUsdt, lpAmount, feeUsdt, 3);
        emit SoldForU(msg.sender, xmtAmount, usdtOut, feeUsdt);
    }

    function _requireClubMember(address user) internal view {
        require(address(clubManager) != address(0), "clubManager not set");
        require(clubManager.memberClubOf(user) > 0, "not club member");
    }
}