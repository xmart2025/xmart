// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "./AdminRoleUpgrade.sol";
import "./interfaces/IXMTStake.sol";
import "./interfaces/IXMTTradePoint.sol";
import "./interfaces/IXMTLiquidityManager.sol";
import "./interfaces/IXMTUsdtDistributor.sol";
import "./interfaces/IXMTTradeDex.sol";
import "./interfaces/IXMTClubManager.sol";
import "./interfaces/IAllowedContracts.sol";

contract XMTEntryPoint is AdminRoleUpgrade, Initializable {

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    event StakeAmountLog(address addr, uint256 status, uint256 amount, bool isAdd, address from);

    mapping(address => uint256) public userAmount;
    IXMTStake public stakeView;
    IXMTTradePoint public tradePoint;
    IERC20Upgradeable public usdt;
    IXMTLiquidityManager public lm;
    IXMTUsdtDistributor public distributor;
    IERC20Upgradeable public xmtToken;
    IXMTTradeDex public dex;
    uint256 public totalQuota;
    uint256 public usedQuota;

    struct DepositRequest {
        address user;
        uint256 amount;
    }

    DepositRequest[] private _queue;
    uint256 private _queueHead;
    address public treasuryAddr;
    IXMTClubManager public clubManager;
    IAllowedContracts public allowedContracts;

    event DepositQueued(uint256 indexed index, address indexed user, uint256 amount);
    event DepositProcessed(uint256 indexed index, address indexed user, uint256 amountProcessed, uint256 energyAdded);
    event DepositPartiallyProcessed(uint256 indexed index, address indexed user, uint256 amountProcessed, uint256 amountRemaining);
    event QuotaUpdated(uint256 totalQuota);

    function setAboutAddress(address _stakeView, address _tradePoint, address _usdt, address _lm, address _distributor, address _treasury, address _clubManager, address _allowedContracts) external onlyAdmin {
        stakeView = IXMTStake(_stakeView);
        tradePoint = IXMTTradePoint(_tradePoint);
        setUsdtFeeParams(_usdt, _lm, _distributor);
        treasuryAddr = _treasury;
        clubManager = IXMTClubManager(_clubManager);
        allowedContracts = IAllowedContracts(_allowedContracts);
    }

    function updateQuota(uint256 _totalQuota) external onlyAdmin {
        totalQuota += _totalQuota;
        emit QuotaUpdated(totalQuota);
    }

    function getRemainingQuota() external view returns (uint256) {
        return totalQuota - usedQuota;
    }

    function setUsdtFeeParams(address _usdt, address _lm, address _distributor) internal  {
        require(_usdt != address(0) && _lm != address(0) && _distributor != address(0), "zero addr");
        usdt = IERC20Upgradeable(_usdt);
        lm = IXMTLiquidityManager(_lm);
        distributor = IXMTUsdtDistributor(_distributor);
    }

    function setXMTToken(address _xmtToken) external onlyAdmin {
        require(_xmtToken != address(0), "zero xmt token");
        xmtToken = IERC20Upgradeable(_xmtToken);
    }

    function setDex(address _dex) external onlyAdmin {
        require(_dex != address(0), "zero dex");
        dex = IXMTTradeDex(_dex);
    }

    function effectiveFeeBps(address user) public view returns (uint256) {
        uint256 direct = stakeView.getActiveDirectCount(user);
        (bool hasAdvanced, bool hasSenior, bool hasElite, bool hasSuper) = _checkNodeTypes(user);
        if (direct >= 20 || hasSuper) return 2500;
        if (direct >= 10 || hasElite) return 3000;
        if (direct >= 5  || hasSenior) return 3500;
        if (direct >= 2  || hasAdvanced) return 4000;
        return 5000;
    }

    function _checkNodeTypes(address user)
        internal
        view
        returns (bool hasAdvanced, bool hasSenior, bool hasElite, bool hasSuper)
    {
        uint256[] memory mids = stakeView.getMiningIds(user);
        for (uint256 mi = 0; mi < mids.length; mi++) {
            uint256 miningIndex = mids[mi];
            if (stakeView.unusedTimes(user, miningIndex) == 0) continue;
            uint256 nodeId = stakeView.pledgeTypeId(user, miningIndex);
            if (!hasAdvanced && _inRange(nodeId, 301, 304)) { hasAdvanced = true; }
            if (!hasSenior   && _inRange(nodeId, 401, 404)) { hasSenior   = true; }
            if (!hasElite    && _inRange(nodeId, 501, 504)) { hasElite    = true; }
            if (!hasSuper    && nodeId >= 601) { hasSuper    = true; }
            if (hasAdvanced && hasSenior && hasElite && hasSuper) {
                break;
            }
        }
    }

    function _inRange(uint256 v, uint256 lo, uint256 hi) internal pure returns (bool) {
        return v >= lo && v <= hi;
    }

    function initialize() public initializer {
        _addAdmin(msg.sender);
    }

    function addXmtPass(address user, uint256 amount) external onlyAdmin{
        userAmount[user] = userAmount[user].add(amount);
        getEventLog(user, 6, amount, true, address(0));
    }

    function addAmountWithStatus(address user, uint256 amount, uint256 status) external onlyAdmin{
        userAmount[user] = userAmount[user].add(amount);
        getEventLog(user, status, amount, true, msg.sender);
    }

    function subAmountWithStatus(address user, uint256 amount, uint256 status) external onlyAdmin{
        require(userAmount[user] >= amount, "amount not enough");
        userAmount[user] = userAmount[user].sub(amount);
        getEventLog(user, status, amount, false, msg.sender);
    }

   function getEventLog(address addr, uint256 status, uint256 amount, bool isAdd, address from) internal {
        emit StakeAmountLog(addr, status, amount, isAdd, from);
    }

    function withdrawToTrade(uint256 amount) external {
        require(allowedContracts.canTrade(msg.sender), "not trade");
        _requireClubMember(msg.sender);
        require(amount > 0, "amount=0");
        require(userAmount[msg.sender] >= amount, "amount not enough");
        require(address(tradePoint) != address(0), "tradePoint not set");
        require(address(usdt) != address(0) && address(lm) != address(0) && address(distributor) != address(0), "fee params not set");
        uint256 guide18 = lm.getTokenPriceInU();
        uint256 usd18 = amount.mul(guide18).div(1e18);
        uint256 feeBps = effectiveFeeBps(msg.sender);
        uint256 feeUsd18 = usd18.mul(feeBps).div(10000);
        uint256 feeUsdt = _usd18ToUsdt(feeUsd18);
        uint256 lpAmount = 0;
        if (feeUsdt > 0) {
            usdt.safeTransferFrom(msg.sender, address(this), feeUsdt);
            usdt.safeApprove(address(distributor), 0);
            usdt.safeApprove(address(distributor), feeUsdt);
            uint256 lpMinted = distributor.distribute(msg.sender, feeUsdt, IXMTUsdtDistributor.SourceType.Entry);
            lpAmount = lpMinted;
        }
        userAmount[msg.sender] = userAmount[msg.sender].sub(amount);
        tradePoint.receiveWithdraw(msg.sender, amount);
        getEventLog(msg.sender, 7, amount, false, address(tradePoint));
        clubManager.addClubAboutAmountWithSeller(msg.sender, amount, 0, lpAmount, feeUsdt, 4);
        clubManager.addClubAboutAmountWithBuyer(msg.sender, amount, 0, 4);
    }

    function _hasAnyActiveMining(address user) internal view returns (bool) {
        uint256[] memory mids = stakeView.getMiningIds(user);
        for (uint256 i = 0; i < mids.length; i++) {
            if (stakeView.unusedTimes(user, mids[i]) > 0) {
                return true;
            }
        }
        return false;
    }

    function _requireClubMember(address user) internal view {
        require(address(clubManager) != address(0), "clubManager not set");
        require(clubManager.memberClubOf(user) > 0, "not club member");
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

    function enqueueDeposit(uint256 amount) external {
        require(address(xmtToken) != address(0), "xmt token not set");
        require(amount > 0, "amount=0");
        xmtToken.safeTransferFrom(msg.sender, treasuryAddr, amount);
        _queue.push(DepositRequest({user: msg.sender, amount: amount}));
        processQueue(100);
        emit DepositQueued(_queue.length - 1, msg.sender, amount);
    }

    function processQueue(uint256 maxItems) public {

        uint256 remaining = totalQuota - usedQuota;
        if (remaining > 0) {
            uint256 processedItems = 0;
            while (_queueHead < _queue.length && remaining > 0) {
                if (maxItems != 0 && processedItems >= maxItems) break;
                DepositRequest storage req = _queue[_queueHead];
                if (req.amount == 0) {
                    _queueHead += 1;
                    continue;
                }

                uint256 toProcess = req.amount <= remaining ? req.amount : remaining;
                if (address(dex) != address(0)) {
                    dex.addEnergy(req.user, toProcess * 2);
                }
                userAmount[req.user] = userAmount[req.user].add(toProcess);
                getEventLog(req.user, 8, toProcess, true, address(xmtToken));
                usedQuota = usedQuota.add(toProcess);
                remaining = remaining - toProcess;
                if (toProcess == req.amount) {
                    emit DepositProcessed(_queueHead, req.user, toProcess, toProcess * 2);
                    delete _queue[_queueHead];
                    _queueHead += 1;
                } else {
                    req.amount = req.amount - toProcess;
                    emit DepositPartiallyProcessed(_queueHead, req.user, toProcess, req.amount);
                    break;
                }
                processedItems += 1;
            }
        }
    }

    function queueLength() external view returns (uint256) {
        return _queue.length - _queueHead;
    }

    function peekQueue() external view returns (address user, uint256 amount) {
        if (_queueHead >= _queue.length) return (address(0), 0);
        DepositRequest storage req = _queue[_queueHead];
        return (req.user, req.amount);
    }

    function clearUserDataBatch(address[] memory users) external onlyAdmin {
        for (uint256 i = 0; i < users.length; i++) {
            userAmount[users[i]] = 0;
        }
    }
}