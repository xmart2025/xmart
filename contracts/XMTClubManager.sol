// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./AdminRoleUpgrade.sol";
import "./interfaces/IRelation.sol";
import "./interfaces/IXMTPool.sol";

contract XMTClubManager is AdminRoleUpgrade, Initializable {

    using SafeERC20Upgradeable for IERC20Upgradeable;

    IRelation public relation;
    uint256 public nextClubId;
    mapping(address => uint256) public memberClubOf;
    mapping(uint256 => address[]) public clubInvList;

    struct ClubInfo {
        address creator;
        uint256 createdAt;
        uint256 memberCount;
        uint256 lpAmount;
        uint256 depositUsdt;
        uint256 withdrawUsdt;
        uint256 depositXmtAmount;
        uint256 withdrawXmtAmount;
        uint256 feeUsdt;
    }

    mapping(uint256 => ClubInfo) public clubInfo;
    mapping(uint256 => bool) public onlyClubOTC;
    uint256 private constant JOIN_DEPOSIT_DEFAULT = 10 * 1e18;
    mapping(uint256 => uint256) public clubJoinDepositAmount;
    mapping(uint256 => uint256) public clubJoinDepositTotal;
    mapping(uint256 => bool) public clubJoinDepositEnabled;
    IERC20Upgradeable public usdt;
    IXMTPool public pool;
    mapping(uint256 => bool) private _clubAllowExternalOTC;

    event ClubCreated(uint256 indexed clubId, address indexed creator);
    event Joined(uint256 indexed clubId, address indexed user);
    event AddClubLp(uint256 indexed clubId, address indexed user, uint256 amount, uint256 status);
    event AddClubDepositUsdt(uint256 indexed clubId, address indexed user, uint256 amount, uint256 status);
    event AddClubWithdrawUsdt(uint256 indexed clubId, address indexed user, uint256 amount, uint256 status);
    event AddClubDepositXmt(uint256 indexed clubId, address indexed user, uint256 amount, uint256 status);
    event AddClubWithdrawXmt(uint256 indexed clubId, address indexed user, uint256 amount, uint256 status);
    event AddClubFeeUsdt(uint256 indexed clubId, address indexed user, uint256 amount, uint256 status);
    event ClubJoinDepositStatusUpdated(uint256 indexed clubId, bool enabled);
    event ClubJoinDepositPaid(uint256 indexed clubId, address indexed user, uint256 amount);
    event ClubJoinDepositAmountUpdated(uint256 indexed clubId, uint256 amount);
    event OnlyClubOTCUpdated(uint256 indexed clubId, bool onlyOTC);
    event ClubCreatorUpdated(uint256 indexed clubId, address indexed oldCreator, address indexed newCreator);
    event ClubOTCExternalStatusUpdated(uint256 indexed clubId, bool allowExternal);

    function initialize() public initializer {
        _addAdmin(msg.sender);
        nextClubId = 10000;
    }

    function setAboutAddress(address _relation, address _pool, address _usdt) external onlyAdmin {
        require(_relation != address(0), "zero addr");
        relation = IRelation(_relation);
        pool = IXMTPool(_pool);
        usdt = IERC20Upgradeable(_usdt);
    }

    function isUnderUmbrella(address user, address root) public view returns (bool) {
        if (user == address(0) || root == address(0)) return false;
        if (user == root) return true;
        address p = user;
        while (p != address(0)) {
            if (p == root) return true;
            p = relation.Inviter(p);
        }
        return false;
    }

    function createClub(address creator) external onlyAdmin returns (uint256 clubId) {
        clubId = _createClubInternal(creator);
    }

    function batchCreateClub(address[] calldata creators) external onlyAdmin returns (uint256[] memory clubIds) {
        clubIds = new uint256[](creators.length);
        for (uint256 i = 0; i < creators.length; i++) {
            clubIds[i] = _createClubInternal(creators[i]);
        }
    }

    function _createClubInternal(address creator) internal returns (uint256 clubId) {
        require(creator != address(0), "creator zero addr");
        require(memberClubOf[creator] == 0, "already in club");
        clubId = nextClubId;
        nextClubId = nextClubId + 1;
        clubInfo[clubId] = ClubInfo({
            creator: creator,
            createdAt: block.timestamp,
            memberCount: 1,
            lpAmount: 0,
            depositUsdt: 0,
            withdrawUsdt: 0,
            depositXmtAmount: 0,
            withdrawXmtAmount: 0,
            feeUsdt: 0
        });
        memberClubOf[creator] = clubId;
        clubInvList[clubId].push(creator);
        emit ClubCreated(clubId, creator);
        emit Joined(clubId, creator);
    }

    function joinClub(uint256 clubId) external {
        require(clubInfo[clubId].creator != address(0), "club not exists");
        require(memberClubOf[msg.sender] == 0, "already in club");
        address creator = clubInfo[clubId].creator;
        require(isUnderUmbrella(msg.sender, creator), "not under creator");

        if (clubJoinDepositEnabled[clubId]) {
            uint256 amount = clubJoinDepositAmount[clubId];
            require(amount > 0, "join deposit zero");
            require(address(usdt) != address(0), "join token unset");
            
            usdt.transferFrom(msg.sender, address(this), amount);
            
            clubJoinDepositTotal[clubId] = clubJoinDepositTotal[clubId] + amount;
            emit ClubJoinDepositPaid(clubId, msg.sender, amount);
            require(address(pool) != address(0), "pool unset");
            pool.giveNodeToUser(msg.sender, 101);
        }
        memberClubOf[msg.sender] = clubId;
        clubInfo[clubId].memberCount = clubInfo[clubId].memberCount + 1;
        clubInvList[clubId].push(msg.sender);
        emit Joined(clubId, msg.sender);
    }

    function getClubInvList(uint256 clubId)
        external
        view
        returns (address[] memory _addrsList)
    {
        _addrsList = new address[](clubInvList[clubId].length);
        for (uint256 i = 0; i < clubInvList[clubId].length; i++) {
            _addrsList[i] = clubInvList[clubId][i];
        }
    }

    function addClubLpWithAddress(address user, uint256 amount, uint256 status) public onlyAdmin {

        uint256 clubId = memberClubOf[user];
        if (clubId > 0 && amount > 0) {
            require(clubInfo[clubId].creator != address(0), "club not exists");
            clubInfo[clubId].lpAmount = clubInfo[clubId].lpAmount + amount;
            emit AddClubLp(clubId, user, amount, status);
        }
    }

    function addClubDepositUsdtWithAddress(address user, uint256 amount, uint256 status) public onlyAdmin {

        uint256 clubId = memberClubOf[user];
        if (clubId > 0 && amount > 0) {
            require(clubInfo[clubId].creator != address(0), "club not exists");
            clubInfo[clubId].depositUsdt = clubInfo[clubId].depositUsdt + amount;
            emit AddClubDepositUsdt(clubId, user, amount, status);
        }
    }

    function addClubWithdrawUsdtWithAddress(address user, uint256 amount, uint256 status) public onlyAdmin {

        uint256 clubId = memberClubOf[user];
        if (clubId > 0 && amount > 0) {
            require(clubInfo[clubId].creator != address(0), "club not exists");
            clubInfo[clubId].withdrawUsdt = clubInfo[clubId].withdrawUsdt + amount;
            emit AddClubWithdrawUsdt(clubId, user, amount, status);
        }
    }

    function addClubDepositXmtWithAddress(address user, uint256 amount, uint256 status) public onlyAdmin {

        uint256 clubId = memberClubOf[user];
        if (clubId > 0 && amount > 0) {
            require(clubInfo[clubId].creator != address(0), "club not exists");
            clubInfo[clubId].depositXmtAmount = clubInfo[clubId].depositXmtAmount + amount;
            emit AddClubDepositXmt(clubId, user, amount, status);
        }
    }

    function addClubWithdrawXmtWithAddress(address user, uint256 amount, uint256 status) public onlyAdmin {

        uint256 clubId = memberClubOf[user];
        if (clubId > 0 && amount > 0) {
            require(clubInfo[clubId].creator != address(0), "club not exists");
            clubInfo[clubId].withdrawXmtAmount = clubInfo[clubId].withdrawXmtAmount + amount;
            emit AddClubWithdrawXmt(clubId, user, amount, status);
        }
    }

    function addClubFeeUsdtWithAddress(address user, uint256 amount, uint256 status) public onlyAdmin {

        uint256 clubId = memberClubOf[user];
        if (clubId > 0 && amount > 0) {
            require(clubInfo[clubId].creator != address(0), "club not exists");
            clubInfo[clubId].feeUsdt = clubInfo[clubId].feeUsdt + amount;
            emit AddClubFeeUsdt(clubId, user, amount, status);
        }
    }

    function addClubAboutAmountWithSeller(address seller, uint256 xmtAmount, uint256 usdtAmount, uint256 lpAmount, uint256 feeUsdtAmount, uint256 status) external onlyAdmin {
        addClubLpWithAddress(seller, lpAmount, status);
        addClubFeeUsdtWithAddress(seller, feeUsdtAmount, status);
        addClubWithdrawXmtWithAddress(seller, xmtAmount, status);
        addClubDepositUsdtWithAddress(seller, usdtAmount, status);
    }

    function addClubAboutAmountWithBuyer(address buyer, uint256 xmtAmount, uint256 usdtAmount, uint256 status) external onlyAdmin {
        addClubWithdrawUsdtWithAddress(buyer, usdtAmount, status);
        addClubDepositXmtWithAddress(buyer, xmtAmount, status);
    }

    function getClubInfo(uint256 clubId) external view returns (ClubInfo memory) {
        return clubInfo[clubId];
    }

    function getClubInfos(uint256[] memory clubIds) external view returns (ClubInfo[] memory) {
        ClubInfo[] memory clubInfos = new ClubInfo[](clubIds.length);
        for (uint256 i = 0; i < clubIds.length; i++) {
            clubInfos[i] = clubInfo[clubIds[i]];
        }
        return clubInfos;
    }

    function getClubJoinDepositTotals(uint256[] memory clubIds) external view returns (uint256[] memory totals) {
        totals = new uint256[](clubIds.length);
        for (uint256 i = 0; i < clubIds.length; i++) {
            totals[i] = clubJoinDepositTotal[clubIds[i]];
        }
    }

    function setClubJoinDepositStatus(uint256 clubId, bool enabled) external {
        ClubInfo storage info = clubInfo[clubId];
        require(info.creator != address(0), "club not exists");
        require(msg.sender == info.creator || isAdmin(msg.sender), "no permission");
        if (clubJoinDepositEnabled[clubId] != enabled) {
            clubJoinDepositEnabled[clubId] = enabled;
            if (enabled && clubJoinDepositAmount[clubId] == 0) {
                clubJoinDepositAmount[clubId] = JOIN_DEPOSIT_DEFAULT;
                emit ClubJoinDepositAmountUpdated(clubId, JOIN_DEPOSIT_DEFAULT);
            }
            emit ClubJoinDepositStatusUpdated(clubId, enabled);
        }
    }

    function clubAllowExternalOTC(uint256 clubId) public view returns (bool) {
        return _clubAllowExternalOTC[clubId];
    }

    function setClubOTCExternalStatus(uint256 clubId, bool allowExternal) external {
        ClubInfo storage info = clubInfo[clubId];
        require(info.creator != address(0), "club not exists");
        require(msg.sender == info.creator || isAdmin(msg.sender), "no permission");
        require(onlyClubOTC[clubId], "club not internal");
        if (_clubAllowExternalOTC[clubId] != allowExternal) {
            _clubAllowExternalOTC[clubId] = allowExternal;
            emit ClubOTCExternalStatusUpdated(clubId, allowExternal);
        }
    }

    function setOnlyClubOTC(uint256 clubId, bool onlyOTC) public {
        _setClubOTCConfig(clubId, onlyOTC, false, false);
    }

    function _setClubOTCConfig(uint256 clubId, bool onlyOTC, bool updateExternal, bool allowExternal) internal {
        ClubInfo storage info = clubInfo[clubId];
        require(info.creator != address(0), "club not exists");
        require(msg.sender == info.creator || isAdmin(msg.sender), "no permission");
        if (onlyClubOTC[clubId] != onlyOTC) {
            onlyClubOTC[clubId] = onlyOTC;
            emit OnlyClubOTCUpdated(clubId, onlyOTC);
        }
        if (updateExternal && _clubAllowExternalOTC[clubId] != allowExternal) {
            _clubAllowExternalOTC[clubId] = allowExternal;
            emit ClubOTCExternalStatusUpdated(clubId, allowExternal);
        }
    }

    function setClubCreator(uint256 clubId, address newCreator) external onlyAdmin {
        ClubInfo storage info = clubInfo[clubId];
        require(info.creator != address(0), "club not exists");
        require(newCreator != address(0), "new creator zero addr");
        require(newCreator != info.creator, "same creator");
        address oldCreator = info.creator;
        info.creator = newCreator;
        uint256 newCreatorClub = memberClubOf[newCreator];
        if (newCreatorClub == 0) {
            memberClubOf[newCreator] = clubId;
            clubInfo[clubId].memberCount = clubInfo[clubId].memberCount + 1;
            clubInvList[clubId].push(newCreator);
            emit Joined(clubId, newCreator);
        } else {
            require(newCreatorClub == clubId, "new creator not in club");
        }
        emit ClubCreatorUpdated(clubId, oldCreator, newCreator);
    }
}