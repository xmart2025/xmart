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
import "./interfaces/IXMTEntryPoint.sol";
import "./interfaces/IXMTTradeQuota.sol";
import "./interfaces/IXMTClubManager.sol";
import "./interfaces/IXMTClubTraderManage.sol";
import "./interfaces/IAllowedContracts.sol";

contract XMTOTC is AdminRoleUpgrade, Initializable {

    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable public usdt;
    IXMTLiquidityManager public lm;
    IXMTUsdtDistributor public distributor;
    IXMTTradePoint public tradePoint;
    IXMTEntryPoint public entryPoint;
    IXMTTradeQuota public tradeQuota;
    uint256 public constant MAX_PER_ORDER_XMT = 500 * 1e18;
    uint256 public constant FEE_BPS = 2000;

    struct Order {
        address seller;
        uint256 amountXMT;
        uint256 price18AtCreation;
        bool canceled;
        bool filled;
        uint256 prepaidFeeUsdt;
        uint256 guide18AtCreation;
    }

    struct BuyOrder {
        address buyer;
        uint256 amountXMT;
        uint256 price18AtCreation;
        bool canceled;
        bool filled;
        uint256 usdtLocked;
        uint256 guide18AtCreation;
    }

    uint256 public nextOrderId;
    mapping(uint256 => Order) public orders;
    uint256 public nextBuyOrderId;
    mapping(uint256 => BuyOrder) public buyOrders;
    IXMTClubManager public clubManager;
    mapping(uint256 => uint256) public orderCreatorClubId;
    mapping(uint256 => uint256) public buyOrderCreatorClubId;
    IAllowedContracts public allowedContracts;
    IXMTClubTraderManage public traderManager;
    uint8 private constant REBATE_CHANNEL_OTC_SELL_ORDER = 3;
    uint8 private constant REBATE_CHANNEL_OTC_BUY_ORDER = 4;
    uint8 private constant REBATE_CHANNEL_OTC_QUICK = 5;

    event OrderPlaced(uint256 indexed orderId, address indexed seller, uint256 amountXMT, uint256 price18, uint256 feeBps, uint256 feeUSDT, uint256 guide18, uint256 clubId);
    event OrderCanceled(uint256 indexed orderId, address indexed seller, uint256 amountXMT);
    event OrderFilled(uint256 indexed orderId, address indexed buyer, uint256 amountXMT, uint256 usdtPaid, uint256 price18AtFill);
    event BuyOrderPlaced(uint256 indexed orderId, address indexed buyer, uint256 amountXMT, uint256 price18, uint256 feeBps, uint256 feeUSDT, uint256 usdtLocked, uint256 guide18, uint256 clubId);
    event BuyOrderCanceled(uint256 indexed orderId, address indexed buyer, uint256 usdtRefunded);
    event BuyOrderFilled(uint256 indexed orderId, address indexed seller, uint256 amountXMT, uint256 usdtPaidOut, uint256 price18AtFill);
    event TraderRebatePaid(address indexed trader, uint256 amount, uint8 channel);

    function initialize() public initializer {
        _addAdmin(msg.sender);
        nextOrderId = 1;
        nextBuyOrderId = 1;
    }

    function setAboutAddress(

        address _usdt,
        address _lm,
        address _distributor,
        address _tradePoint,
        address _entryPoint,
        address _tradeQuota,
        address _clubManager,
        address _allowedContracts,
        address _traderManager
    ) external onlyAdmin {
        require(
            _usdt != address(0) &&
            _lm != address(0) &&
            _distributor != address(0) &&
            _tradePoint != address(0) &&
            _entryPoint != address(0) &&
            _tradeQuota != address(0) &&
            _clubManager != address(0) &&
            _allowedContracts != address(0) &&
            _traderManager != address(0),
            "zero addr"
        );
        usdt = IERC20Upgradeable(_usdt);
        lm = IXMTLiquidityManager(_lm);
        distributor = IXMTUsdtDistributor(_distributor);
        tradePoint = IXMTTradePoint(_tradePoint);
        entryPoint = IXMTEntryPoint(_entryPoint);
        tradeQuota = IXMTTradeQuota(_tradeQuota);
        clubManager = IXMTClubManager(_clubManager);
        allowedContracts = IAllowedContracts(_allowedContracts);
        traderManager = IXMTClubTraderManage(_traderManager);
    }

    function placeSellOrder(uint256 amountXMT, uint256 askPrice18) external returns (uint256 orderId) {
        _requireClubMember(msg.sender);
        require(amountXMT > 0, "amount=0");
        require(amountXMT <= MAX_PER_ORDER_XMT, "exceeds per-order cap");
        uint256 guide18 = lm.getTokenPriceInU();
        require(askPrice18 > 0, "price=0");
        uint256 minPrice = guide18.mul(90).div(100);
        uint256 maxPrice = guide18.mul(110).div(100);
        require(askPrice18 >= minPrice && askPrice18 <= maxPrice, "price out of 10% range");
        uint256 usdtValue18 = amountXMT.mul(guide18).div(1e18);
        uint256 feeUsd18 = usdtValue18.mul(FEE_BPS).div(10000);
        uint256 feeUsdt = _usd18ToUsdt(feeUsd18);
        if (feeUsdt > 0) {
            usdt.safeTransferFrom(msg.sender, address(this), feeUsdt);
        }
        require(address(tradePoint) != address(0), "tradePoint not set");
        tradePoint.subAmountWithStatus(msg.sender, amountXMT, 2);
        orderId = nextOrderId++;
        orders[orderId] = Order({
            seller: msg.sender,
            amountXMT: amountXMT,
            price18AtCreation: askPrice18,
            canceled: false,
            filled: false,
            prepaidFeeUsdt: feeUsdt,
            guide18AtCreation: guide18
        });
        uint256 creatorClubId = clubManager.memberClubOf(msg.sender);
        orderCreatorClubId[orderId] = creatorClubId;
        emit OrderPlaced(orderId, msg.sender, amountXMT, askPrice18, FEE_BPS, feeUsdt, guide18, creatorClubId);
    }

    function cancel(uint256 orderId) external {
        Order storage od = orders[orderId];
        require(od.seller != address(0), "no order");
        require(!od.canceled && !od.filled, "closed");
        require(msg.sender == od.seller, "only seller");
        od.canceled = true;
        uint256 refund = od.prepaidFeeUsdt;
        od.prepaidFeeUsdt = 0;
        if (refund > 0) {
            usdt.safeTransfer(od.seller, refund);
        }
        require(address(tradePoint) != address(0), "tradePoint not set");
        tradePoint.addAmountWithStatus(od.seller, od.amountXMT, 5);
        emit OrderCanceled(orderId, od.seller, od.amountXMT);
    }

    function buyOrder(uint256 orderId) external {
        _requireClubMember(msg.sender);
        Order storage od = orders[orderId];
        require(od.seller != address(0), "no order");
        require(!od.canceled && !od.filled, "closed");
        (bool sellerIsTrader, bool buyerIsTrader) = _resolveTraders(od.seller, msg.sender);
        uint256 requiredClubId = orderCreatorClubId[orderId];
        _checkBuyerClubAccess(msg.sender, requiredClubId);
        uint256 price18 = od.price18AtCreation;
        uint256 usd18 = od.amountXMT.mul(price18).div(1e18);
        uint256 usdtPay = _usd18ToUsdt(usd18);
        usdt.safeTransferFrom(msg.sender, od.seller, usdtPay);
        od.filled = true;
        require(address(entryPoint) != address(0), "entryPoint not set");
        if (_isTrader(msg.sender)) {
            require(address(tradePoint) != address(0), "tradePoint not set");
            tradePoint.addAmountWithStatus(msg.sender, od.amountXMT, 8);
        } else {
            entryPoint.addAmountWithStatus(msg.sender, od.amountXMT, 11);
        }

        uint256 feeUsdt = od.prepaidFeeUsdt;
        od.prepaidFeeUsdt = 0;
        uint256 lpAmount = 0;
        uint256 distributorFeeUsdt = _applyTraderRebate(
            od.seller,
            sellerIsTrader,
            msg.sender,
            buyerIsTrader,
            feeUsdt,
            REBATE_CHANNEL_OTC_SELL_ORDER
        );
        if (distributorFeeUsdt > 0) {
            usdt.safeApprove(address(distributor), 0);
            usdt.safeApprove(address(distributor), distributorFeeUsdt);
            uint256 lpMinted = distributor.distribute(od.seller, distributorFeeUsdt, IXMTUsdtDistributor.SourceType.Trade);
            lpAmount = lpMinted;
        }
        tradeQuota.updateOTCVolume(od.amountXMT);
        tradeQuota.recordTrade(od.price18AtCreation, od.guide18AtCreation, od.amountXMT);
        clubManager.addClubAboutAmountWithSeller(od.seller, od.amountXMT, usdtPay-feeUsdt, lpAmount, distributorFeeUsdt, 2);
        clubManager.addClubAboutAmountWithBuyer(msg.sender, od.amountXMT, usdtPay, 2);
        emit OrderFilled(orderId, msg.sender, od.amountXMT, usdtPay, price18);
    }

    function placeBuyOrder(uint256 amountXMT, uint256 bidPrice18) external returns (uint256 orderId) {
        _requireClubMember(msg.sender);
        require(amountXMT > 0, "amount=0");
        require(amountXMT <= MAX_PER_ORDER_XMT, "exceeds per-order cap");
        uint256 guide18 = lm.getTokenPriceInU();
        require(bidPrice18 > 0, "price=0");
        uint256 minPrice = guide18.mul(90).div(100);
        uint256 maxPrice = guide18.mul(110).div(100);
        require(bidPrice18 >= minPrice && bidPrice18 <= maxPrice, "price out of 10% range");
        uint256 usdtValue18 = amountXMT.mul(bidPrice18).div(1e18);
        uint256 lockUsdt = _usd18ToUsdt(usdtValue18);
        if (lockUsdt > 0) {
            usdt.safeTransferFrom(msg.sender, address(this), lockUsdt);
        }
        orderId = nextBuyOrderId++;
        buyOrders[orderId] = BuyOrder({
            buyer: msg.sender,
            amountXMT: amountXMT,
            price18AtCreation: bidPrice18,
            canceled: false,
            filled: false,
            usdtLocked: lockUsdt,
            guide18AtCreation: guide18
        });
        uint256 creatorClubId = clubManager.memberClubOf(msg.sender);
        buyOrderCreatorClubId[orderId] = creatorClubId;
        emit BuyOrderPlaced(orderId, msg.sender, amountXMT, bidPrice18, FEE_BPS, 0, lockUsdt, guide18, creatorClubId);
    }

    function cancelBuyOrder(uint256 orderId) external {
        BuyOrder storage bo = buyOrders[orderId];
        require(bo.buyer != address(0), "no order");
        require(!bo.canceled && !bo.filled, "closed");
        require(msg.sender == bo.buyer, "only buyer");
        bo.canceled = true;
        uint256 refund = bo.usdtLocked;
        bo.usdtLocked = 0;
        if (refund > 0) {
            usdt.safeTransfer(bo.buyer, refund);
        }
        emit BuyOrderCanceled(orderId, bo.buyer, refund);
    }

    function sellToBuyOrder(uint256 orderId) external {
        _requireClubMember(msg.sender);
        BuyOrder storage bo = buyOrders[orderId];
        require(bo.buyer != address(0), "no order");
        require(!bo.canceled && !bo.filled, "closed");
        (bool sellerIsTrader, bool buyerIsTrader) = _resolveTraders(msg.sender, bo.buyer);
        uint256 requiredClubId = buyOrderCreatorClubId[orderId];
        _checkSellerClubAccess(msg.sender, requiredClubId);
        uint256 price18 = bo.price18AtCreation;
        uint256 usd18 = bo.amountXMT.mul(price18).div(1e18);
        uint256 usdtPay = _usd18ToUsdt(usd18);
        require(usdtPay <= bo.usdtLocked, "insufficient lock");
        require(address(tradePoint) != address(0), "tradePoint not set");
        tradePoint.subAmountWithStatus(msg.sender, bo.amountXMT, 2);
        uint256 feeUsd18 = bo.amountXMT.mul(bo.guide18AtCreation).div(1e18).mul(FEE_BPS).div(10000);
        uint256 feeUsdt = _usd18ToUsdt(feeUsd18);
        require(feeUsdt <= usdtPay, "fee>pay");
        uint256 sellerReceive = usdtPay - feeUsdt;
        bo.filled = true;
        bo.usdtLocked = bo.usdtLocked - usdtPay;
        if (sellerReceive > 0) {
            usdt.safeTransfer(msg.sender, sellerReceive);
        }

        uint256 lpAmount = 0;
        uint256 distributorFeeUsdt = _applyTraderRebate(
            msg.sender,
            sellerIsTrader,
            bo.buyer,
            buyerIsTrader,
            feeUsdt,
            REBATE_CHANNEL_OTC_BUY_ORDER
        );
        if (distributorFeeUsdt > 0) {
            usdt.safeApprove(address(distributor), 0);
            usdt.safeApprove(address(distributor), distributorFeeUsdt);
            uint256 lpMinted = distributor.distribute(msg.sender, distributorFeeUsdt, IXMTUsdtDistributor.SourceType.Trade);
            lpAmount = lpMinted;
        }
        require(address(entryPoint) != address(0), "entryPoint not set");
        if (_isTrader(bo.buyer)) {
            require(address(tradePoint) != address(0), "tradePoint not set");
            tradePoint.addAmountWithStatus(bo.buyer, bo.amountXMT, 8);
        } else {
            entryPoint.addAmountWithStatus(bo.buyer, bo.amountXMT, 11);
        }
        tradeQuota.updateOTCVolume(bo.amountXMT);
        tradeQuota.recordTrade(bo.price18AtCreation, bo.guide18AtCreation, bo.amountXMT);
        clubManager.addClubAboutAmountWithSeller(msg.sender, bo.amountXMT, sellerReceive, lpAmount, distributorFeeUsdt, 2);
        clubManager.addClubAboutAmountWithBuyer(bo.buyer, bo.amountXMT, usdtPay, 2);
        emit BuyOrderFilled(orderId, msg.sender, bo.amountXMT, sellerReceive, price18);
    }

    function OTCQuickTrade(uint256 orderId) external {
		require(allowedContracts.canTrade(msg.sender), "not trade");
		_requireClubMember(msg.sender);
		BuyOrder storage bo = buyOrders[orderId];
		require(bo.buyer != address(0), "no order");
		require(!bo.canceled && !bo.filled, "closed");
		uint256 requiredClubId = buyOrderCreatorClubId[orderId];
        _checkSellerClubAccess(msg.sender, requiredClubId);
		address seller = msg.sender;
		uint256 amountXMT = bo.amountXMT;
		require(amountXMT > 0, "amount=0");
        (bool sellerIsTrader, bool buyerIsTrader) = _resolveTraders(seller, bo.buyer);
		uint256 usd18 = amountXMT.mul(bo.price18AtCreation).div(1e18);
		uint256 usdtPay = _usd18ToUsdt(usd18);
		require(usdtPay <= bo.usdtLocked, "insufficient lock");
		require(address(entryPoint) != address(0) && address(tradePoint) != address(0), "points not set");
		entryPoint.subAmountWithStatus(seller, amountXMT, 7);
		tradePoint.addAmountWithStatus(seller, amountXMT, 4);
		tradePoint.subAmountWithStatus(seller, amountXMT, 2);
		uint256 entryUsd18 = amountXMT.mul(bo.guide18AtCreation).div(1e18);
		uint256 entryFeeBps = entryPoint.effectiveFeeBps(seller);
		uint256 entryFeeUsd18 = entryUsd18.mul(entryFeeBps).div(10000);
		uint256 entryFeeUsdt = _usd18ToUsdt(entryFeeUsd18);
		uint256 tradeUsd18 = amountXMT.mul(bo.guide18AtCreation).div(1e18);
		uint256 tradeFeeUsd18 = tradeUsd18.mul(FEE_BPS).div(10000);
		uint256 tradeFeeUsdt = _usd18ToUsdt(tradeFeeUsd18);
		require(entryFeeUsdt + tradeFeeUsdt <= usdtPay, "fee>pay");
		bo.filled = true;
		bo.usdtLocked = bo.usdtLocked - usdtPay;
		uint256 sellerReceive = usdtPay - entryFeeUsdt - tradeFeeUsdt;
		if (sellerReceive > 0) {
			usdt.safeTransfer(seller, sellerReceive);
		}

        uint256 lpentryAmount = 0;
        uint256 entryFeeForDistributor = entryFeeUsdt;
		if (entryFeeUsdt > 0) {
			usdt.safeApprove(address(distributor), 0);
			if (entryFeeForDistributor > 0) {
                usdt.safeApprove(address(distributor), entryFeeForDistributor);
			    uint256 lpMinted1 = distributor.distribute(msg.sender, entryFeeForDistributor, IXMTUsdtDistributor.SourceType.Entry);
                lpentryAmount = lpMinted1;
            }
		}

        uint256 lpAmount = 0;
        uint256 tradeFeeForDistributor = tradeFeeUsdt;
		if (tradeFeeUsdt > 0) {
            tradeFeeForDistributor = _applyTraderRebate(
                seller,
                sellerIsTrader,
                bo.buyer,
                buyerIsTrader,
                tradeFeeUsdt,
                REBATE_CHANNEL_OTC_QUICK
            );
			usdt.safeApprove(address(distributor), 0);
            if (tradeFeeForDistributor > 0) {
			    usdt.safeApprove(address(distributor), tradeFeeForDistributor);
			    uint256 lpMinted = distributor.distribute(msg.sender, tradeFeeForDistributor, IXMTUsdtDistributor.SourceType.Trade);
                lpAmount = lpMinted;
            }
		}
		if (_isTrader(bo.buyer)) {
            require(address(tradePoint) != address(0), "tradePoint not set");
            tradePoint.addAmountWithStatus(bo.buyer, amountXMT, 8);
        } else {
            entryPoint.addAmountWithStatus(bo.buyer, amountXMT, 11);
        }
		tradeQuota.updateOTCVolume(amountXMT);
		tradeQuota.recordTrade(bo.price18AtCreation, bo.guide18AtCreation, amountXMT);
        clubManager.addClubAboutAmountWithSeller(msg.sender, bo.amountXMT, sellerReceive, lpAmount, tradeFeeForDistributor, 2);
        clubManager.addClubAboutAmountWithBuyer(bo.buyer, bo.amountXMT, usdtPay, 2);
        clubManager.addClubAboutAmountWithSeller(msg.sender, bo.amountXMT, 0, lpentryAmount, entryFeeForDistributor, 4);
        clubManager.addClubAboutAmountWithBuyer(bo.buyer, bo.amountXMT, 0, 4);
		emit BuyOrderFilled(orderId, seller, amountXMT, sellerReceive, bo.price18AtCreation);
	}

    function _resolveTraders(address partyA, address partyB) internal view returns (bool isTraderA, bool isTraderB) {
        if (address(traderManager) == address(0)) {
            return (false, false);
        }
        return (traderManager.isTrader(partyA), traderManager.isTrader(partyB));
    }

    function _applyTraderRebate(

        address partyA,
        bool partyATrader,
        address partyB,
        bool partyBTrader,
        uint256 feeUsdt,
        uint8 channel
    ) internal returns (uint256 distributorFeeUsdt) {
        if (feeUsdt == 0 || (!partyATrader && !partyBTrader)) {
            return feeUsdt;
        }
        if (partyATrader && partyBTrader) {
            uint256 half = feeUsdt / 2;
            if (half > 0) {
                usdt.safeTransfer(partyA, half);
                emit TraderRebatePaid(partyA, half, channel);
                usdt.safeTransfer(partyB, half);
                emit TraderRebatePaid(partyB, half, channel);
            }

            uint256 remainder = feeUsdt - half - half;
            if (remainder > 0) {
                usdt.safeTransfer(partyA, remainder);
                emit TraderRebatePaid(partyA, remainder, channel);
            }
            return 0;
        }

        address trader = partyATrader ? partyA : partyB;
        uint256 rebateUsdt = feeUsdt / 2;
        if (rebateUsdt > 0) {
            usdt.safeTransfer(trader, rebateUsdt);
            emit TraderRebatePaid(trader, rebateUsdt, channel);
        }
        return feeUsdt - rebateUsdt;
    }

    function _isTrader(address account) internal view returns (bool) {
        return address(traderManager) != address(0) && traderManager.isTrader(account);
    }

    function _usd18ToUsdt(uint256 usd18) internal view returns (uint256) {
        (bool ok, bytes memory data) = address(usdt).staticcall(abi.encodeWithSignature("decimals()"));
        if (!ok || data.length == 0) {
            return usd18;
        }

        uint8 dec = abi.decode(data, (uint8));
        if (dec == 18) return usd18;
        if (dec > 18) return usd18.mul(10 ** (dec - 18));
        return usd18 / (10 ** (18 - dec));
    }

    function _checkSellerClubAccess(address seller, uint256 buyerClubId) internal view {

        uint256 sellerClubId = clubManager.memberClubOf(seller);
        if (buyerClubId > 0 && clubManager.onlyClubOTC(buyerClubId)) {
            require(sellerClubId == buyerClubId, "club internal only");
        }
        if (
            sellerClubId > 0 &&
            clubManager.onlyClubOTC(sellerClubId) &&
            !clubManager.clubAllowExternalOTC(sellerClubId)
        ) {
            require(buyerClubId == sellerClubId, "club external disabled");
        }
    }

    function _checkBuyerClubAccess(address buyer, uint256 sellerClubId) internal view {

        uint256 buyerClubId = clubManager.memberClubOf(buyer);
        if (sellerClubId > 0 && clubManager.onlyClubOTC(sellerClubId)) {
            require(buyerClubId == sellerClubId, "club internal only");
        }
    }

    function _requireClubMember(address user) internal view {
        require(address(clubManager) != address(0), "clubManager not set");
        require(clubManager.memberClubOf(user) > 0, "not club member");
    }
}