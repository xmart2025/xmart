// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./AdminRoleUpgrade.sol";
import "./interfaces/IXMTLiquidityManager.sol";
import "./interfaces/IXMTClubManager.sol";

interface IXMTDividendTransactionFee {

    function collectIncome(uint256 amount) external;
}

contract XMTUsdtDistributor is AdminRoleUpgrade, Initializable {

    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    enum SourceType {
        Default,
        Entry,
        Trade
    }

    IERC20Upgradeable public usdt;
    IERC20Upgradeable public xmt;
    IXMTLiquidityManager public lm;
    address public dividend;
    address public treasury;
    address public burnSink;
    address public cityNodeFee;
    IXMTClubManager public clubManager;

    event Distributed(
        address indexed payer,
        uint256 usdtIn,
        uint256 usdtForBuy,
        uint256 usdtForLiquidity,
        uint256 lpMinted,
        uint256 xmtBought,
        uint256 xmtToDividend,
        uint256 sourceType
    );

    event VirtualDistributionSimulated(
        address indexed payer,
        uint256 usdtIn,
        uint256 usdtForBuy,
        uint256 usdtForLiquidity,
        uint256 virtualXmtBought,
        uint256 virtualTokenForLiquidity,
        uint256 virtualXmtForDividend,
        uint256 price18,
        uint256 sourceType
    );

    function initialize() public initializer {
        _addAdmin(msg.sender);
        burnSink = address(0xdead);
    }

    function setAboutAddress(address _usdt, address _xmt, address _lm, address _dividend, address _treasury,  address _cityNodeFee, address _clubManager) external onlyAdmin{
        usdt = IERC20Upgradeable(_usdt);
        xmt = IERC20Upgradeable(_xmt);
        lm = IXMTLiquidityManager(_lm);
        dividend = _dividend;
        treasury = _treasury;
        cityNodeFee = _cityNodeFee;
        clubManager = IXMTClubManager(_clubManager);
    }

    function setBurnSink(address _sink) external onlyAdmin {
        require(_sink != address(0), "zero sink");
        burnSink = _sink;
    }

    function distribute(address addr, uint256 usdtAmount, SourceType source) external returns (uint256) {
        require(source == SourceType.Entry || source == SourceType.Trade, "source error");
        require(usdtAmount > 0, "amount=0");
        
        usdt.safeTransferFrom(msg.sender, address(this), usdtAmount);
        
        if(IXMTLiquidityManager(address(lm)).isOpenVirtualPrice()){
            (
                uint256 usdtForBuyVirtual,
                uint256 usdtForLiquidityVirtual,
                uint256 virtualXmtBought,
                uint256 virtualTokenForLiquidity,
                uint256 virtualXmtForDividend,
                uint256 price18
            ) = _simulateVirtualDistribution(usdtAmount);
            uint256 xmtForDividend = virtualXmtForDividend;
            if (xmtForDividend > 0) {
                if (source == SourceType.Entry) {
                    IXMTDividendTransactionFee(dividend).collectIncome(xmtForDividend);
                } else if (source == SourceType.Trade) {
                    IXMTDividendTransactionFee(cityNodeFee).collectIncome(xmtForDividend);
                }
            }
            emit VirtualDistributionSimulated(
                addr,
                usdtAmount,
                usdtForBuyVirtual,
                usdtForLiquidityVirtual,
                virtualXmtBought,
                virtualTokenForLiquidity,
                virtualXmtForDividend,
                price18,
                uint256(source)
            );
            return 0;
        }

        uint256 usdtForLiquidity = usdtAmount.div(4);
        uint256 usdtForBuy = usdtAmount.sub(usdtForLiquidity);
        usdt.safeApprove(address(lm), 0);
        usdt.safeApprove(address(lm), usdtAmount);
        uint256 xmtBefore = xmt.balanceOf(address(this));
        IXMTLiquidityManager(address(lm)).buyTokenWithU(usdtForBuy, 0, address(this));
        uint256 xmtBought = xmt.balanceOf(address(this)).sub(xmtBefore);
        require(xmtBought > 0, "no XMT bought");
        xmt.safeTransfer(address(lm), xmtBought);
        (uint256 lpMinted, , uint256 tokenUsed) = IXMTLiquidityManager(address(lm)).addLiquidityFromCaller(usdtForLiquidity, xmtBought, treasury);
        uint256 xmtForDividend = xmt.balanceOf(address(this)).sub(xmtBefore);
        if (xmtForDividend > 0) {
            if (source == SourceType.Entry) {
                IXMTDividendTransactionFee(dividend).collectIncome(xmtForDividend);
            } else if (source == SourceType.Trade) {
                IXMTDividendTransactionFee(cityNodeFee).collectIncome(xmtForDividend);
            }
        }
        xmt.safeTransfer(treasury, xmtForDividend);
        emit Distributed(
            addr,
            usdtAmount,
            usdtForBuy,
            usdtForLiquidity,
            lpMinted,
            xmtBought,
            xmtForDividend,
            uint256(source)
        );
        return lpMinted;
    }

    function _burnOrSink(uint256 amount) internal {
        if (amount == 0) return;
        xmt.safeTransfer(burnSink, amount);
    }

    function _simulateVirtualDistribution(uint256 usdtAmount)
        internal
        view
        returns (
            uint256 usdtForBuy,
            uint256 usdtForLiquidity,
            uint256 virtualXmtBought,
            uint256 virtualTokenForLiquidity,
            uint256 virtualXmtForDividend,
            uint256 price18
        )
    {
        usdtForLiquidity = usdtAmount.div(4);
        usdtForBuy = usdtAmount.sub(usdtForLiquidity);
        price18 = IXMTLiquidityManager(address(lm)).getTokenPriceInU();
        require(price18 > 0, "price=0");
        uint8 usdtDecimals = IERC20MetadataUpgradeable(address(usdt)).decimals();
        uint8 xmtDecimals = IERC20MetadataUpgradeable(address(xmt)).decimals();
        virtualXmtBought = _convertUToToken(usdtForBuy, price18, usdtDecimals, xmtDecimals);
        virtualTokenForLiquidity = _convertUToToken(usdtForLiquidity, price18, usdtDecimals, xmtDecimals);
        if (virtualXmtBought > virtualTokenForLiquidity) {
            virtualXmtForDividend = virtualXmtBought.sub(virtualTokenForLiquidity);
        } else {
            virtualXmtForDividend = 0;
        }
    }

    function _convertUToToken(

        uint256 uAmount,
        uint256 price18,
        uint8 uDecimals,
        uint8 tokenDecimals
    ) internal pure returns (uint256 tokenAmount) {
        require(price18 > 0, "price=0");
        uint256 base = 10 ** 18;
        if (tokenDecimals >= uDecimals) {
            uint256 scale = 10 ** (uint256(tokenDecimals) - uint256(uDecimals));
            tokenAmount = uAmount.mul(scale).mul(base).div(price18);
        } else {
            uint256 scale = 10 ** (uint256(uDecimals) - uint256(tokenDecimals));
            tokenAmount = uAmount.mul(base).div(price18).div(scale);
        }
    }
}