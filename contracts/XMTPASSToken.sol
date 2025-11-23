// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract XMTPassToken is ERC20Burnable {
    uint256 private constant TOTAL_SUPPLY = 1000_000_000 * 10 ** 18;

    constructor() ERC20("MARTPOINT Token", "MART") {
        _mint(address(this), TOTAL_SUPPLY);
    }
}