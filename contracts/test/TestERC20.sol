// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.0;

import "../libraries/ERC20Detailed.sol";
import "../libraries/ERC20Mintable.sol";

contract TestERC20 is ERC20Detailed, ERC20Mintable {
    constructor(uint amount) ERC20Detailed('Test ERC20', 'TEST', 18) ERC20Mintable() public {
        mint(msg.sender, amount);
    }
}
