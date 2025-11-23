// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./AdminRoleUpgrade.sol";

contract XMTTreasury is AdminRoleUpgrade, Initializable {

    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public xmtToken;

    event Deposited(address indexed from, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);

    function initialize() public initializer {
        _addAdmin(msg.sender);
    }

    function setXmtToken(address _xmtToken) public onlyAdmin {
        require(_xmtToken != address(0), "token zero");
        xmtToken = _xmtToken;
    }

    function deposit(uint256 amount) external onlyAdmin {
        require(amount > 0, "amount zero");
        IERC20Upgradeable(xmtToken).safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(msg.sender, amount);
    }

    function depositFrom(address from, uint256 amount) external onlyAdmin {
        require(amount > 0, "amount zero");
        IERC20Upgradeable(xmtToken).safeTransferFrom(from, address(this), amount);
        emit Deposited(from, amount);
    }

    function withdraw(address to, uint256 amount) external onlyAdmin {
        require(to != address(0), "to zero");
        require(amount > 0, "amount zero");
        IERC20Upgradeable(xmtToken).safeTransfer(to, amount);
        emit Withdrawn(to, amount);
    }

    function balance() external view returns (uint256) {
        return IERC20Upgradeable(xmtToken).balanceOf(address(this));
    }
}