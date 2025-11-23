// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./AdminRoleUpgrade.sol";

contract XMTPassManage is AdminRoleUpgrade, Initializable {

    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable public passToken;
    address public passBurn;
    uint256 public constant REFILL_AMOUNT = 100_000_000 * 10**18;

    event RefilledToBurn(address indexed burnContract, uint256 amount);

    function initialize() public initializer {
        _addAdmin(msg.sender);
    }

    function setAboutAddress(address _token, address _burn) external onlyAdmin {
        require(_token != address(0), "zero token");
        require(_burn != address(0), "zero burn");
        passToken = IERC20Upgradeable(_token);
        passBurn = _burn;
    }

    function refillToBurn() external onlyAdmin {
        require(address(passToken) != address(0), "token not set");
        uint256 balance = passToken.balanceOf(address(this));
        uint256 amount = balance >= REFILL_AMOUNT ? REFILL_AMOUNT : balance;
        require(amount > 0, "insufficient balance");
        passToken.safeTransfer(passBurn, amount);
        emit RefilledToBurn(passBurn, amount);
    }
}