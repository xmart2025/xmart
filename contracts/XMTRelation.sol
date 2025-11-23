// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "./AdminRoleUpgrade.sol";
import "./interfaces/IXMTEntryPoint.sol";

contract XMTRelation is AdminRoleUpgrade, Initializable {

    event Bind(address parent, address child);

    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;

    mapping(address => address) public Inviter;
    mapping(address => bool) public invStats;
    mapping(address => address[]) public invList;
    mapping(address => address[]) public activeList;

    function initialize() public initializer {
        _addAdmin(msg.sender);
        invStats[0x0000000000000000000000000000000000000001] = true;
    }

    function bind(address inv)
    external
    {
        require(!invStats[msg.sender], "BIND ERROR: ONCE BIND");
        require(invStats[inv], "BIND ERROR: INVITER NOT BIND YET");
        _bind(msg.sender, inv);
    }

    function mintBind(address child, address parent)
    external onlyAdmin
    {
        require(!invStats[child], "BIND ERROR: ONCE BIND");
        require(invStats[parent], "BIND ERROR: INVITER NOT BIND YET");
        _bind(child, parent);
    }

    function _bind(address addr, address inv)
    internal
    {
        Inviter[addr] = inv;
        invList[inv].push(addr);
        invStats[addr] = true;
        emit Bind(inv, addr);
    }

    function BatchBind(address[] memory childs, address[] memory parents)
        external
        onlyAdmin
    {
        require(childs.length == parents.length, "BATCH BIND: arrays length mismatch");
        for (uint256 i = 0; i < childs.length; i++) {
            address child = childs[i];
            address parent = parents[i];
            require(!invStats[child], "BIND ERROR: ONCE BIND");
            require(invStats[parent], "BIND ERROR: INVITER NOT BIND YET");
            _bind(child, parent);
        }
    }

    function invListLength(address addr_) public view returns (uint256) {
        return invList[addr_].length;
    }

    function getInvList(address addr_)
        public
        view
        returns (address[] memory _addrsList)
    {
        _addrsList = new address[](invList[addr_].length);
        for (uint256 i = 0; i < invList[addr_].length; i++) {
            _addrsList[i] = invList[addr_][i];
        }
    }

    function batchBindByParent(address parent, address[] memory addrs) external onlyAdmin{
        require(invStats[parent], "BIND ERROR: INVITER NOT BIND YET");
        for (uint256 i = 0; i < addrs.length; i++) {
            if(!invStats[addrs[i]]){
                _bind(addrs[i], parent);
            }
        }
    }

    function batchAddrBindStatus(address[] memory addrs) external view returns(bool[] memory){
        bool[] memory bindstatus = new bool[](addrs.length);
        for (uint256 index = 0; index < addrs.length; index++) {
            bindstatus[index] = invStats[addrs[index]];
        }
        return bindstatus;
    }

    function batchBindWithParentAndChild(address[] memory childs, address[] memory parents) external onlyAdmin{
        for (uint256 index = 0; index < childs.length; index++) {
            if(!invStats[childs[index]]){
                _bind(childs[index], parents[index]);
            }
        }
    }

    function forceRebind(address child, address newParent) external onlyAdmin {
        require(child != address(0) && newParent != address(0), "BIND ERROR: ZERO ADDRESS");
        require(invStats[newParent], "BIND ERROR: INVITER NOT BIND YET");
        address oldParent = Inviter[child];
        if (oldParent != address(0) && oldParent != newParent) {
            _removeChildFromParent(oldParent, child);
        }
        Inviter[child] = newParent;
        if (!invStats[child]) {
            invStats[child] = true;
        }
        invList[newParent].push(child);
        if(child != 0xF0E7d34f59Ab564003Eb8aa88d647049bb9855cD){
            emit Bind(newParent, child);
        }
    }

    function _removeChildFromParent(address parent, address child) internal {
        address[] storage children = invList[parent];
        for (uint256 i = 0; i < children.length; i++) {
            if (children[i] == child) {
                if (i != children.length - 1) {
                    children[i] = children[children.length - 1];
                }
                children.pop();
                return;
            }
        }
        revert("BIND ERROR: CHILD NOT FOUND");
    }
}