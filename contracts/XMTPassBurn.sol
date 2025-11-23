// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./AdminRoleUpgrade.sol";

interface IXMTPassManage {

    function refillToBurn() external;
}

contract XMTPassBurn is AdminRoleUpgrade, Initializable {

    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable public passToken;
    address public passManage;
    uint256 public constant REFILL_AMOUNT = 100_000_000 * 10**18;
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    event Burned(address indexed token, uint256 amount);
    event Refilled(uint256 amount);

    function initialize() public initializer {
        _addAdmin(msg.sender);
    }

    function setAboutAddress(address _token, address _manage) external onlyAdmin {
        require(_token != address(0), "zero token");
        require(_manage != address(0), "zero manage");
        passToken = IERC20Upgradeable(_token);
        passManage = _manage;
    }

    function burn(uint256 amount) external {
        require(amount > 0, "amount=0");
        require(address(passToken) != address(0), "token not set");
        uint256 balance = passToken.balanceOf(address(this));
        if (balance < amount) {
            IXMTPassManage(passManage).refillToBurn();
        }
        passToken.safeTransfer(DEAD_ADDRESS, amount);
        emit Burned(address(passToken), amount);
    }
}