// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "./AdminRoleUpgrade.sol";
import "./interfaces/IRelation.sol";
import "./interfaces/IXMTUsdtDistributor.sol";
import "./interfaces/IXMTLiquidityManager.sol";
import "./interfaces/IXMTTradePoint.sol";
import "./interfaces/IXMTEntryPoint.sol";
import "./interfaces/IXMTTradeQuota.sol";
import "./interfaces/IXMTClubManager.sol";
import "./interfaces/IXMTClubTraderManage.sol";
import "./interfaces/IAllowedContracts.sol";

contract XMTGift is AdminRoleUpgrade, Initializable {

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    IRelation public relation;
    uint256 public MAX_GENERATIONS;
    IERC20Upgradeable public usdtToken;
    uint256 public feeBps;
    address public liquidityManager;
    IXMTUsdtDistributor public distributor;
    IXMTTradePoint public tradePoint;
    IXMTEntryPoint public entryPoint;
    IXMTTradeQuota public tradeQuota;

    event GiftToUpline(address indexed from, address indexed toUpline, uint256 amount);
    event GiftToDownline(address indexed from, address indexed toDownline, uint256 amount);

    uint8 private constant COD_PENDING = 1;
    uint8 private constant COD_SETTLED = 2;
    uint8 private constant COD_CANCELLED = 3;

    struct CODOrder {
        address seller;
        address buyer;
        uint256 amount;
        uint256 createdAt;
        uint8 status;
        uint256 settlePrice18;
    }

    uint256 public nextCodId;
    mapping(uint256 => CODOrder) public codOrders;
    IXMTClubManager public clubManager;
    IXMTClubTraderManage public traderManager;
    IAllowedContracts public allowedContracts;
    mapping(uint256 => bool) public codOrderIsQuickPay;
    uint8 private constant REBATE_CHANNEL_C2C_COD = 1;
    uint8 private constant REBATE_CHANNEL_C2C_GIFT = 2;

    event CodCreated(uint256 indexed orderId, address indexed seller, address indexed buyer, uint256 amount);
    event CodSettled(uint256 indexed orderId, address indexed buyer, uint256 price18, uint256 usdtGross, uint256 usdtFee, uint256 usdtNet);
    event CodCancelled(uint256 indexed orderId, address indexed seller);
    event TraderRebatePaid(address indexed trader, uint256 amount, uint8 channel);

    function initialize() public initializer {
        _addAdmin(msg.sender);
        MAX_GENERATIONS = 45;
        feeBps = 1000;
    }

    function setAboutAddress(

        address _relation,
        address _usdt,
        address _lm,
        address _distributor,
        address _tradePoint,
        address _entryPoint,
        address _tradeQuota,
        address _clubManager,
        address _traderManager,
        address _allowedContracts
    ) external onlyAdmin {
        require(
            _relation != address(0) &&
            _usdt != address(0) &&
            _lm != address(0) &&
            _distributor != address(0) &&
            _tradePoint != address(0) &&
            _entryPoint != address(0) &&
            _tradeQuota != address(0) &&
            _clubManager != address(0) &&
            _traderManager != address(0) &&
            _allowedContracts != address(0),
            "zero addr"
        );
        relation = IRelation(_relation);
        usdtToken = IERC20Upgradeable(_usdt);
        liquidityManager = _lm;
        distributor = IXMTUsdtDistributor(_distributor);
        feeBps = 1000;
        tradePoint = IXMTTradePoint(_tradePoint);
        entryPoint = IXMTEntryPoint(_entryPoint);
        tradeQuota = IXMTTradeQuota(_tradeQuota);
        clubManager = IXMTClubManager(_clubManager);
        traderManager = IXMTClubTraderManage(_traderManager);
        allowedContracts = IAllowedContracts(_allowedContracts);
    }

    function setFeeConfig(uint256 _feeBps) external onlyAdmin {
        require(_feeBps <= 5000, "fee too high");
        feeBps = _feeBps;
    }

    function createCOD(address buyer, uint256 amount) external returns (uint256 orderId) {
        _requireClubMember(msg.sender);
        require(buyer != address(0), "zero addr");
        require(amount > 0, "amount zero");
        address seller = msg.sender;
        require(_checkRelationWithTrader(buyer, seller), "no relation");
        require(address(tradePoint) != address(0) && address(entryPoint) != address(0), "tp/ep unset");
        tradePoint.subAmountWithStatus(seller, amount, 1);
        if (nextCodId == 0) {
            nextCodId = 1;
        }
        orderId = nextCodId++;
        codOrders[orderId] = CODOrder({
            seller: seller,
            buyer: buyer,
            amount: amount,
            createdAt: block.timestamp,
            status: COD_PENDING,
            settlePrice18: 0
        });
        emit CodCreated(orderId, seller, buyer, amount);
    }

    function createCODQuick(address buyer, uint256 amount) external returns (uint256 orderId) {
        require(allowedContracts.canTrade(msg.sender), "not trade");
        _requireClubMember(msg.sender);
        require(buyer != address(0), "zero addr");
        require(amount > 0, "amount zero");
        address seller = msg.sender;
        require(_checkRelationWithTrader(buyer, seller), "no relation");
        require(address(tradePoint) != address(0) && address(entryPoint) != address(0), "tp/ep unset");
        entryPoint.subAmountWithStatus(seller, amount, 7);
        tradePoint.addAmountWithStatus(seller, amount, 4);
        tradePoint.subAmountWithStatus(seller, amount, 1);
        if (nextCodId == 0) {
            nextCodId = 1;
        }
        orderId = nextCodId++;
        codOrders[orderId] = CODOrder({
            seller: seller,
            buyer: buyer,
            amount: amount,
            createdAt: block.timestamp,
            status: COD_PENDING,
            settlePrice18: 0
        });
        codOrderIsQuickPay[orderId] = true;
        emit CodCreated(orderId, seller, buyer, amount);
    }

    function settleCOD(uint256 orderId) external {
        _requireClubMember(msg.sender);
        CODOrder storage o = codOrders[orderId];
        require(o.status == COD_PENDING, "not pending");
        require(msg.sender == o.buyer, "only buyer");
        require(address(usdtToken) != address(0) && liquidityManager != address(0), "fee conf");
        require(address(distributor) != address(0), "no distributor");
        (bool sellerIsTrader, bool buyerIsTrader) = _resolveTraders(o.seller, o.buyer);
        uint256 price18 = IXMTLiquidityManager(liquidityManager).getTokenPriceInU();
        o.settlePrice18 = price18;
        uint256 usd18 = o.amount.mul(price18).div(1e18);
        uint256 feeUsd18 = usd18.mul(feeBps).div(10000);
        uint8 usdtDec = IERC20MetadataUpgradeable(address(usdtToken)).decimals();
        uint256 payUsdt;
        uint256 feeUsdt;
        if (usdtDec == 18) {
            payUsdt = usd18;
            feeUsdt = feeUsd18;
        } else if (usdtDec > 18) {
            payUsdt = usd18.mul(10 ** (usdtDec - 18));
            feeUsdt = feeUsd18.mul(10 ** (usdtDec - 18));
        } else {
            payUsdt = usd18.div(10 ** (18 - usdtDec));
            feeUsdt = feeUsd18.div(10 ** (18 - usdtDec));
        }
        if (payUsdt > 0) {
            usdtToken.safeTransferFrom(o.buyer, address(this), payUsdt);
        }

        uint256 lpentryAmount = 0;
        uint256 entryFeeUsdt = 0;
        if (codOrderIsQuickPay[orderId]) {
            require(address(entryPoint) != address(0), "entryPoint not set");
            uint256 entryFeeBps = entryPoint.effectiveFeeBps(o.seller);
            uint256 entryFeeUsd18 = usd18.mul(entryFeeBps).div(10000);
            if (usdtDec == 18) {
                entryFeeUsdt = entryFeeUsd18;
            } else if (usdtDec > 18) {
                entryFeeUsdt = entryFeeUsd18.mul(10 ** (usdtDec - 18));
            } else {
                entryFeeUsdt = entryFeeUsd18.div(10 ** (18 - usdtDec));
            }
            require(entryFeeUsdt <= payUsdt, "entry fee > pay");
            if (entryFeeUsdt > 0) {
                usdtToken.safeApprove(address(distributor), 0);
                usdtToken.safeApprove(address(distributor), entryFeeUsdt);
                uint256 lpMinted = distributor.distribute(o.seller, entryFeeUsdt, IXMTUsdtDistributor.SourceType.Entry);
                lpentryAmount = lpMinted;
            }
        }

        uint256 lpAmount = 0;
        uint256 distributorFeeUsdt = _applyTraderRebate(
            o.seller,
            sellerIsTrader,
            o.buyer,
            buyerIsTrader,
            feeUsdt,
            REBATE_CHANNEL_C2C_COD
        );
        if (distributorFeeUsdt > 0) {
            usdtToken.safeApprove(address(distributor), 0);
            usdtToken.safeApprove(address(distributor), distributorFeeUsdt);
            uint256 lpMinted = distributor.distribute(o.seller, distributorFeeUsdt, IXMTUsdtDistributor.SourceType.Trade);
            lpAmount = lpMinted;
        }

        uint256 netUsdt = payUsdt.sub(entryFeeUsdt).sub(feeUsdt);
        if (netUsdt > 0) {
            usdtToken.safeTransfer(o.seller, netUsdt);
        }
        if (_isTrader(msg.sender)) {
            require(address(tradePoint) != address(0), "tradePoint not set");
            tradePoint.addAmountWithStatus(msg.sender, o.amount, 7);
        } else {
            entryPoint.addAmountWithStatus(msg.sender, o.amount, 10);
        }
        o.status = COD_SETTLED;
        tradeQuota.updateC2CVolume(o.amount);
        clubManager.addClubAboutAmountWithSeller(o.seller, o.amount, netUsdt, lpAmount, distributorFeeUsdt, 1);
        clubManager.addClubAboutAmountWithBuyer(o.buyer, o.amount, payUsdt, 1);
        if (codOrderIsQuickPay[orderId]) {
            clubManager.addClubAboutAmountWithSeller(o.seller, o.amount, 0, lpentryAmount, entryFeeUsdt, 4);
            clubManager.addClubAboutAmountWithBuyer(o.buyer, o.amount, 0, 4);
        }
        emit CodSettled(orderId, o.buyer, price18, payUsdt, feeUsdt, netUsdt);
    }

    function cancelCOD(uint256 orderId) external {
        _requireClubMember(msg.sender);
        CODOrder storage o = codOrders[orderId];
        require(o.status == COD_PENDING, "not pending");
        require(msg.sender == o.seller, "only seller");
        require(address(tradePoint) != address(0) && address(entryPoint) != address(0), "tp/ep unset");
        if (codOrderIsQuickPay[orderId]) {
            entryPoint.addAmountWithStatus(o.seller, o.amount, 10);
        } else {
            tradePoint.addAmountWithStatus(o.seller, o.amount, 6);
        }
        o.status = COD_CANCELLED;
        emit CodCancelled(orderId, o.seller);
    }

    function gift(address parent, address child, uint256 amount) external {
        _requireClubMember(msg.sender);
        require(parent != address(0) && child != address(0), "zero addr");
        require(amount > 0, "amount zero");
        require(_checkRelationWithTrader(parent, child), "not same lineage");
        if (msg.sender == parent) {
            _requireClubMember(child);
        } else if (msg.sender == child) {
            _requireClubMember(parent);
        } else {
            revert("not participant");
        }

        address counterparty = msg.sender == parent ? child : parent;
        _collectFeeInUSDTWithStar(msg.sender, counterparty, amount, REBATE_CHANNEL_C2C_GIFT);
        require(address(tradePoint) != address(0) && address(entryPoint) != address(0), "tp/ep unset");
        if (msg.sender == parent) {
            tradePoint.subAmountWithStatus(parent, amount, 1);
            if (_isTrader(child)) {
                tradePoint.addAmountWithStatus(child, amount, 7);
            } else {
            entryPoint.addAmountWithStatus(child, amount, 10);
            }
            emit GiftToDownline(parent, child, amount);
        } else if (msg.sender == child) {
            tradePoint.subAmountWithStatus(child, amount, 1);
            if (_isTrader(parent)) {
                tradePoint.addAmountWithStatus(parent, amount, 7);
            } else {
            entryPoint.addAmountWithStatus(parent, amount, 10);
            }
            emit GiftToUpline(child, parent, amount);
        } else {
            revert("not participant");
        }
        tradeQuota.updateC2CVolume(amount);
    }

    function giftQuick(address parent, address child, uint256 amount) external {
        require(allowedContracts.canTrade(msg.sender), "not trade");
        _requireClubMember(msg.sender);
        require(parent != address(0) && child != address(0), "zero addr");
        require(amount > 0, "amount zero");
        require(_checkRelationWithTrader(parent, child), "not same lineage");
        if (msg.sender == parent) {
            _requireClubMember(child);
        } else if (msg.sender == child) {
            _requireClubMember(parent);
        } else {
            revert("not participant");
        }
        require(address(tradePoint) != address(0) && address(entryPoint) != address(0), "tp/ep unset");
        require(address(usdtToken) != address(0) && liquidityManager != address(0), "fee conf");
        require(address(distributor) != address(0), "no distributor");
        address payer = msg.sender;
        address counterparty = msg.sender == parent ? child : parent;
        entryPoint.subAmountWithStatus(payer, amount, 7);
        tradePoint.addAmountWithStatus(payer, amount, 4);
        uint256 guide18 = IXMTLiquidityManager(liquidityManager).getTokenPriceInU();
        uint256 entryUsd18 = amount.mul(guide18).div(1e18);
        uint256 entryFeeBps = entryPoint.effectiveFeeBps(payer);
        uint256 entryFeeUsd18 = entryUsd18.mul(entryFeeBps).div(10000);
        uint8 usdtDec = IERC20MetadataUpgradeable(address(usdtToken)).decimals();
        uint256 entryFeeUsdt;
        if (usdtDec == 18) {
            entryFeeUsdt = entryFeeUsd18;
        } else if (usdtDec > 18) {
            entryFeeUsdt = entryFeeUsd18.mul(10 ** (usdtDec - 18));
        } else {
            entryFeeUsdt = entryFeeUsd18.div(10 ** (18 - usdtDec));
        }

        uint256 lpentryAmount = 0;
        if (entryFeeUsdt > 0) {
            usdtToken.safeTransferFrom(payer, address(this), entryFeeUsdt);
            usdtToken.safeApprove(address(distributor), 0);
            usdtToken.safeApprove(address(distributor), entryFeeUsdt);
            uint256 lpMinted = distributor.distribute(payer, entryFeeUsdt, IXMTUsdtDistributor.SourceType.Entry);
            lpentryAmount = lpMinted;
        }
        clubManager.addClubAboutAmountWithSeller(payer, amount, 0, lpentryAmount, entryFeeUsdt, 4);
        clubManager.addClubAboutAmountWithBuyer(counterparty, amount, 0, 4);
        _collectFeeInUSDTWithStar(payer, counterparty, amount, REBATE_CHANNEL_C2C_GIFT);
        if (msg.sender == parent) {
            tradePoint.subAmountWithStatus(parent, amount, 1);
            if (_isTrader(child)) {
                tradePoint.addAmountWithStatus(child, amount, 7);
            } else {
                entryPoint.addAmountWithStatus(child, amount, 10);
            }
            emit GiftToDownline(parent, child, amount);
        } else if (msg.sender == child) {
            tradePoint.subAmountWithStatus(child, amount, 1);
            if (_isTrader(parent)) {
                tradePoint.addAmountWithStatus(parent, amount, 7);
            } else {
                entryPoint.addAmountWithStatus(parent, amount, 10);
            }
            emit GiftToUpline(child, parent, amount);
        }
        tradeQuota.updateC2CVolume(amount);
    }

    function isUpline(address user, address potentialAncestor) external view returns (bool) {
        return _checkRelationWithTrader(user, potentialAncestor);
    }

    function _isUpline(address user, address potentialAncestor) internal view returns (bool) {
        if (user == address(0) || potentialAncestor == address(0)) return false;
        address current = relation.Inviter(user);
        uint256 depth = 0;
        while (current != address(0) && depth < MAX_GENERATIONS) {
            if (current == potentialAncestor) return true;
            current = relation.Inviter(current);
            depth++;
        }
        return false;
    }

    function isTrader(address user) external view returns (bool) {
        return traderManager.isTrader(user);
    }

    function _checkRelationWithTrader(address partyA, address partyB) internal view returns (bool) {
        address effectiveA = partyA;
        if (traderManager.isTrader(partyA)) {
            address creatorA = traderManager.traderCreator(partyA);
            if (creatorA == address(0)) return false;
            effectiveA = creatorA;
        }

        address effectiveB = partyB;
        if (traderManager.isTrader(partyB)) {
            address creatorB = traderManager.traderCreator(partyB);
            if (creatorB == address(0)) return false;
            effectiveB = creatorB;
        }
        return _isUpline(effectiveA, effectiveB) || _isUpline(effectiveB, effectiveA);
    }

    function _checkParentChildRelation(address parent, address child) internal view returns (bool) {
        if (address(traderManager) == address(0)) {
            return _isUpline(child, parent);
        }

        address effectiveParent = parent;
        if (traderManager.isTrader(parent)) {
            address creatorParent = traderManager.traderCreator(parent);
            if (creatorParent == address(0)) return false;
            effectiveParent = creatorParent;
        }

        address effectiveChild = child;
        if (traderManager.isTrader(child)) {
            address creatorChild = traderManager.traderCreator(child);
            if (creatorChild == address(0)) return false;
            effectiveChild = creatorChild;
        }
        return _isUpline(effectiveChild, effectiveParent);
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
                usdtToken.safeTransfer(partyA, half);
                emit TraderRebatePaid(partyA, half, channel);
                usdtToken.safeTransfer(partyB, half);
                emit TraderRebatePaid(partyB, half, channel);
            }

            uint256 remainder = feeUsdt - half - half;
            if (remainder > 0) {
                usdtToken.safeTransfer(partyA, remainder);
                emit TraderRebatePaid(partyA, remainder, channel);
            }
            return 0;
        }

        address trader = partyATrader ? partyA : partyB;
        uint256 rebateUsdt = feeUsdt / 2;
        if (rebateUsdt > 0) {
            usdtToken.safeTransfer(trader, rebateUsdt);
            emit TraderRebatePaid(trader, rebateUsdt, channel);
        }
        return feeUsdt - rebateUsdt;
    }

    function _isTrader(address account) internal view returns (bool) {
        return address(traderManager) != address(0) && traderManager.isTrader(account);
    }

    function _collectFeeInUSDTWithStar(address payer, address counterparty, uint256 xmtAmount, uint8 channel) internal {
        require(address(usdtToken) != address(0) && liquidityManager != address(0), "fee conf");
        uint256 price18 = IXMTLiquidityManager(liquidityManager).getTokenPriceInU();
        uint256 usd18 = xmtAmount.mul(price18).div(1e18);
        uint256 feeUsd18 = usd18.mul(feeBps).div(10000);
        uint8 usdtDec = IERC20MetadataUpgradeable(address(usdtToken)).decimals();
        uint256 feeUsdt;
        if (usdtDec == 18) {
            feeUsdt = feeUsd18;
        } else if (usdtDec > 18) {
            feeUsdt = feeUsd18.mul(10 ** (usdtDec - 18));
        } else {
            feeUsdt = feeUsd18.div(10 ** (18 - usdtDec));
        }
        (bool payerIsTrader, bool counterpartyIsTrader) = _resolveTraders(payer, counterparty);
        uint256 distributorFeeUsdt = feeUsdt;
        uint256 lpAmount = 0;
        if (feeUsdt > 0) {
            usdtToken.safeTransferFrom(payer, address(this), feeUsdt);
            require(address(distributor) != address(0), "no distributor");
            usdtToken.safeApprove(address(distributor), 0);
            distributorFeeUsdt = _applyTraderRebate(
                payer,
                payerIsTrader,
                counterparty,
                counterpartyIsTrader,
                feeUsdt,
                channel
            );
            if (distributorFeeUsdt > 0) {
                usdtToken.safeApprove(address(distributor), distributorFeeUsdt);
                uint256 lpMinted = distributor.distribute(payer, distributorFeeUsdt, IXMTUsdtDistributor.SourceType.Trade);
            lpAmount = lpMinted;
            }
        }
        clubManager.addClubAboutAmountWithSeller(payer, xmtAmount, 0, lpAmount, distributorFeeUsdt, 1);
        clubManager.addClubAboutAmountWithBuyer(payer, xmtAmount, 0, 1);
    }

    function getCodOrder(uint256 orderId) external view returns (CODOrder memory) {
        return codOrders[orderId];
    }

    function _requireClubMember(address user) internal view {
        require(address(clubManager) != address(0), "clubManager not set");
        require(clubManager.memberClubOf(user) > 0, "not club member");
    }
}