// SPDX-License-Identifier: GPL-3.0-or-later
// This file is part of DEXCHAIN.
//
// Copyright (c) 2021 Dexio Technologies.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

pragma solidity >=0.5.0;

import './libraries/Math.sol';
import './libraries/SafeMath.sol';
import './libraries/ERC20Detailed.sol';
import './libraries/SafeERC20.sol';
import "./libraries/Address.sol";
import './libraries/ReentrancyGuard.sol';
import './libraries/Ownable.sol';

contract DexchangeCore is ReentrancyGuard, Ownable {
    using Address for address;

    /* ========== STATE VARIABLES ========== */

    // Exchange Rates, 1 DEX's equivalent token price
    mapping(address => uint256) private _exchangePrice;

    /* ========== EVENTS ========== */

    event PriceChanged(
        address token,
        uint256 price
    );

    /* ========== CONSTRUCTOR ========== */

    constructor() public Ownable() {}

    /* ========== MODIFIERS ========== */

    /* ========== VIEWS ========== */

    function price(address token) public view returns (uint256) {
        return _exchangePrice[token];
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function setPrice(address token, uint256 _price) public onlyOwner {
        require(
            token.isContract(), 
            "DexchangeCore::setPrice: call to non-contract"
        );
        _exchangePrice[token] = _price;
        emit PriceChanged(token, _price);
    }
}
