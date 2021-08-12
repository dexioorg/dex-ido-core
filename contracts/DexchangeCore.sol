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
import './DexIDOPool.sol';

contract DexchangeCore is ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

    /* ========== STATE VARIABLES ========== */

    // Uinx timestamp of 2021/08/01 0:00:00
    uint256 private AUGUST = 1627747200; 
    // Stop contract function
    bool private _stopped;
    // Reward rate for referrals(‰), use permil, eg: value 12 equals 12‰=1.2%
    uint16 private _rewardRate;
    // DEX IDO pool contract
    address private _poolAddr;
    // IDO pool number
    uint32 private _poolNum;
    // Exchange Rates, 1 DEX's equivalent token price
    mapping(address => uint256) private _exchangePrice;
    // Invitation map of accounts
    mapping(address => address) private _invitations;
    // Total exchanged amount of DEX
    uint256 private _totalExchange;
    // The account's daily exchanged amount of DEX
    mapping(uint256 => mapping(address => uint256)) private _dailyExchange;

    /* ========== EVENTS ========== */

    event PriceChanged(
        address token,
        uint256 price
    );
    event PoolChanged(
        address pool,
        uint32 poolNum
    );
    event RewardRateChanged(
        uint16 rewardRate
    );
    event Bought(address sender, uint256 amount, address token, uint256 price);

    /* ========== CONSTRUCTOR ========== */

    constructor() public Ownable() {}

    /* ========== MODIFIERS ========== */

    modifier stoppable {
        require(!_stopped, 'DexchangeCore::stoppable: contract has been stopped.');
        _;
    }

    /* ========== VIEWS ========== */

    function stopped() public view returns (bool) {
        return _stopped;
    }

    function rewardRate() public view returns (uint16) {
        return _rewardRate;
    }

    function poolAddress() public view returns (address) {
        return _poolAddr;
    }

    function poolNumber() public view returns (uint32) {
        return _poolNum;
    }

    function exchanged() public view returns (uint256) {
        return _totalExchange;
    }

    function price(address token) public view returns (uint256) {
        return _exchangePrice[token];
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stop() public onlyOwner {
        _stopped = true;
    }

    function start() public onlyOwner {
        _stopped = false;
    }

    function setRewardRate(uint16 rate) public onlyOwner {
        require(
            rate < 1000,
            "DexchangeCore::setRewardRate: reward rate use permil"
        );
        _rewardRate = rate;
        emit RewardRateChanged(rate);
    }

    function setPoolAddress(address addr) public onlyOwner {
        require(
            address(addr) != address(0),
            "DexchangeCore::setPoolAddress: pool address is invalid"
        );
        _poolAddr = addr;
        emit PoolChanged(addr, 0);
    }

    function setPoolNumber(uint32 num) public onlyOwner {
        _poolNum = num;
        emit PoolChanged(address(0), _poolNum);
    }

    function setPrice(address token, uint256 _price) public onlyOwner {
        require(
            token.isContract(), 
            "DexchangeCore::setPrice: call to non-contract"
        );
        require(
            _price > 0, 
            "DexchangeCore::setPrice: price is invalid"
        );
        _exchangePrice[token] = _price;
        emit PriceChanged(token, _price);
    }

    /*
        Account accept invitation from referrer. 
    */
    function acceptInvitation(address referrer) public stoppable {
        // require referrer has deposited.
        DexIDOPool pool = DexIDOPool(_poolAddr);
        require(
            pool.balanceOf(_poolNum, referrer) > 0,
            "DexchangeCore::acceptInvitation: referrer did not deposit DEX"
        );

        require(
            _invitations[msg.sender] == address(0),
            "DexchangeCore::acceptInvitation: has been accepted invitation"
        );

        _invitations[msg.sender] = referrer;
    }
    
    /*
        deposit DEX to the pool
    */
    function buy(address token, uint256 amount) public payable nonReentrant stoppable {
        
        require(
            token.isContract(), 
            "DexchangeCore::setPrice: call to non-contract."
        );

        require(
            amount > 0,
            "DexchangeCore::buy: input amount is invalid."
        );

        uint256 _price = _exchangePrice[token];

        require(
            _price > 0,
            "DexchangeCore::buy: do not support the token."
        );

        IERC20 tokenContract = IERC20(token);

        uint256 totalAmount = amount.mul(_price);

        require(
            tokenContract.balanceOf(msg.sender) >= totalAmount,
            "DexchangeCore::buy: token balance is insufficient"
        );

        // fetch available DEX amount, and subtract the bought amount
        DexIDOPool pool = DexIDOPool(_poolAddr);
        uint256 available = pool.availableToExchange(_poolNum, msg.sender);
        uint256 day = (block.timestamp - AUGUST) / 1 days;
        uint256 today = _dailyExchange[day][msg.sender];

        require(
            available - today > amount,
            "DexchangeCore::buy: amount exceeds the available amount"
        );

        // calculate the referral rewards
        uint256 rewards = amount.mul(_rewardRate).div(1000);
        address inviter1 = _invitations[msg.sender];
        if (inviter1 != address(0)) {
            // 1st level referrer
            uint256 reward1 = 0;
            uint256 reward2 = 0;
            uint256 reward3 = 0;
            uint256 reward4 = 0;
            uint256 reward5 = 0;
            address inviter2 = _invitations[inviter1];
            address inviter3 = address(0);
            address inviter4 = address(0);
            address inviter5 = address(0);
            if (inviter2 != address(0)) {
                // 2st level referrer
                inviter3 = _invitations[inviter2];
                if (inviter3 != address(0)) {
                    // 3st level referrer
                    inviter4 = _invitations[inviter3];
                    if (inviter4 != address(0)) {
                        inviter5 = _invitations[inviter4];
                        if (inviter5 != address(0)) {
                            // 5 level referrers
                            reward5 = rewards.div(5);
                            reward4 = reward5;
                            reward3 = reward4;
                            reward2 = reward3;
                            reward1 = rewards.sub(reward2).sub(reward3);
                            reward1 = reward1.sub(reward4).sub(reward5);
                            
                        } else {
                            // only 4 level referrers
                            reward4 = rewards.div(5);
                            reward3 = reward4;
                            reward2 = reward3;
                            reward1 = rewards.sub(reward2).sub(reward3);
                            reward1 = reward1.sub(reward4);
                        }
                    } else {
                        // only 3 level referrers
                        reward3 = rewards.div(5);
                        reward2 = reward3;
                        reward1 = rewards.sub(reward2).sub(reward3);
                    }
                } else {
                    // only 2 level referrers
                    reward2 = rewards.div(5);
                    reward1 = rewards.sub(reward2);
                }
            } else {
                // only 1 level referrer
                reward1 = rewards;
            }

            // send DEX reward to inviters  
            address(uint160(inviter1)).transfer(reward1);
            if (reward2 > 0) {
                address(uint160(inviter2)).transfer(reward2);
            }
            if (reward3 > 0) {
                address(uint160(inviter3)).transfer(reward3);
            }
            if (reward4 > 0) {
                address(uint160(inviter4)).transfer(reward4);
            }
            if (reward5 > 0) {
                address(uint160(inviter5)).transfer(reward5);
            }
        }

        // send token to Contract
        tokenContract.safeTransferFrom(msg.sender, address(this), totalAmount);
    
        _totalExchange = _totalExchange + amount;

        _dailyExchange[day][msg.sender] = today + amount;

        // send DEX to sender, subtract rewards
        msg.sender.transfer(amount - rewards);

        emit Bought(msg.sender, amount, token, _price);
    }

}
