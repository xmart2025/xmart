// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./AdminRoleUpgrade.sol";
import "./interfaces/IXMTClubManager.sol";
import "./interfaces/IRelation.sol";

contract XMTClubTraderManage is AdminRoleUpgrade, Initializable {
    IXMTClubManager public clubManager;
    IRelation public relation;
    mapping(address => bool) private _isTrader;
    mapping(address => address) private _traderCreator;
    mapping(address => address[]) private _creatorTraders;
    mapping(address => mapping(address => uint256)) private _traderIndex;

    event TraderAdded(address indexed creator, address indexed trader);
    event TraderRemoved(address indexed creator, address indexed trader);
    event AddressesUpdated(address indexed clubManager, address indexed relation);

    function initialize() public initializer {
        _addAdmin(msg.sender);
    }

    function setAboutAddress(address _clubManager, address _relation) external onlyAdmin {
        require(_clubManager != address(0) && _relation != address(0), "zero addr");
        clubManager = IXMTClubManager(_clubManager);
        relation = IRelation(_relation);
        emit AddressesUpdated(_clubManager, _relation);
    }

    function adminAddTrader(address creator, address trader) external onlyAdmin {
        _requireReady();
        require(trader != address(0), "trader zero");
        require(!_isTrader[trader], "already trader");
        require(trader != creator, "self invalid");
        _requireCreator(creator);
        require(relation.Inviter(trader) == creator, "not direct subordinate");
        _isTrader[trader] = true;
        _traderCreator[trader] = creator;
        _creatorTraders[creator].push(trader);
        _traderIndex[creator][trader] = _creatorTraders[creator].length;
        emit TraderAdded(creator, trader);
    }

    function removeTrader(address trader) external {
        _requireReady();
        require(_isTrader[trader], "not trader");
        address creator = _traderCreator[trader];
        require(isAdmin(msg.sender), "no permission");
        delete _isTrader[trader];
        delete _traderCreator[trader];
        uint256 idxPlus = _traderIndex[creator][trader];
        if (idxPlus > 0) {
            uint256 idx = idxPlus - 1;
            address[] storage traders = _creatorTraders[creator];
            uint256 lastIdx = traders.length - 1;
            if (idx != lastIdx) {
                address lastTrader = traders[lastIdx];
                traders[idx] = lastTrader;
                _traderIndex[creator][lastTrader] = idx + 1;
            }
            traders.pop();
            delete _traderIndex[creator][trader];
        }
        emit TraderRemoved(creator, trader);
    }

    function isTrader(address account) external view returns (bool) {
        return _isTrader[account];
    }

    function traderCreator(address trader) external view returns (address) {
        return _traderCreator[trader];
    }

    function getCreatorTraders(address creator) external view returns (address[] memory) {
        return _creatorTraders[creator];
    }

    function getCreatorTraderCount(address creator) external view returns (uint256) {
        return _creatorTraders[creator].length;
    }

    function _requireCreator(address account) internal view {

        uint256 clubId = clubManager.memberClubOf(account);
        require(clubId != 0, "not join club");
        (address creator,,,,,,, ,) = clubManager.clubInfo(clubId);
        require(creator == account, "not creator");
    }

    function _requireReady() internal view {
        require(address(clubManager) != address(0) && address(relation) != address(0), "addresses not set");
    }
}