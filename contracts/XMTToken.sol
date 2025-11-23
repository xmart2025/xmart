// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract XMTToken is ERC20Burnable {
    
    constructor() ERC20("XMT Token", "XMT") {
        _mint(msg.sender, 10_000_000_000 * 10 ** 18);

    }
}