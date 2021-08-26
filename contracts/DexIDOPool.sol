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
import './libraries/ReentrancyGuard.sol';
import './libraries/Ownable.sol';
import './DexchangeCore.sol';

contract DexIDOPool is ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

    /* ========== STATE VARIABLES ========== */

    struct IDOPool {
        uint256 start; // IDO pool starting time
        uint256 duration; // IDO pool duration
        uint256 totalAmount; // Total supply DEX amount of the pool
        uint256 limitPerDay; // Daily exchange limit
        uint16 rewardRate; // Reward rate for referrals(‰), use permil, eg: value 12 equals 12‰=1.2%
        address top; // top referrer
        address creator; // IDO pool creator
    }

    // Stop contract function
    bool private _stopped;
    // Pool pool
    IDOPool private _poolInfo;
    // DexchangeCore contract address
    address private _dexchangeAddr;
    // Total deposited amount of the pool
    uint256 private _totalDepositOf;
    // Total exchanged amount of DEX
    uint256 private _totalExchange;
    // Deposited amount of the address in the pool
    mapping(address => uint256) private _balanceOf;
    // Daily deposited amount of the pool
    mapping(uint256 => uint256) private _dailyDeposit;
    // Daily deposited amount of the address in the pool
    mapping(uint256 => mapping(address => uint256)) private _dailyDepositOf;
    // The account's daily exchanged amount of DEX
    mapping(uint256 => mapping(address => uint256)) private _dailyExchange;
    // Invitation map of accounts
    mapping(address => address) private _invitations;

    /* ========== EVENTS ========== */

    event Deployed(uint256 start, uint256 duration, uint256 totalAmount, uint256 limitPerDay, uint16 rewardRate, address creator, address dexchange, address top);
    event Deposited(address sender, uint256 amount);
    event Withdrawn(address sender, uint256 amount);
    event Bought(address sender, uint256 amount, address token, uint256 price);

    /* ========== CONSTRUCTOR ========== */

    constructor() public Ownable() {}

    /* ========== MODIFIERS ========== */

    modifier stoppable() {
        require(!_stopped, 'DexIDOPool::stoppable: contract has been stopped.');
        _;
    }

    /* ========== VIEWS ========== */

    function stopped() public view returns (bool) {
        return _stopped;
    }

    // total deposited amount
    function totalDeposit() public view returns (uint256) {
        return _totalDepositOf;
    }

    // deposit DEX balance of the account
    function balanceOf(address account) public view returns (uint256) {
        return _balanceOf[account];
    }

    // available DEX amount for the account today
    function availableToExchange(address account) public view returns (uint256) {
        IDOPool storage pool = _poolInfo;

        if (pool.start > block.timestamp) {
            return 0;
        }
        if (block.timestamp > (pool.start + pool.duration)) {
            return 0;
        }

        uint256 TODAY = (block.timestamp - pool.start) / 1 days;
        uint256 balance = _balanceOf[account].sub(_dailyDepositOf[TODAY][account]);
        uint256 total = _totalDepositOf.sub(_dailyDeposit[TODAY]);
        if (_totalDepositOf == _dailyDeposit[TODAY]) {
            return 0;
        }

        uint256 available = balance.mul(pool.limitPerDay).div(total);

        return available;
    }

    // total exchanged
    function exchanged() public view returns (uint256) {
        return _totalExchange;
    }

    // pool starting time
    function poolStart() public view returns (uint256) {
        return _poolInfo.start;
    }

    // pool duration
    function poolDuration() public view returns (uint256) {
        return _poolInfo.duration;
    }

    // total supply DEX amount of the pool 
    function poolTotal() public view returns (uint256) {
        return _poolInfo.totalAmount;
    }

    // supply DEX amount daily
    function poolDailyLimit() public view returns (uint256) {
        return _poolInfo.limitPerDay;
    }

    // exchanged DEX amount of the date
    // date - unix timestamp of zero hour UTC+0
    function exchangedDaily(uint256 date) public view returns (uint256) {
        uint256 TODAY = (date - _poolInfo.start) / 1 days;
        return _dailyDeposit[TODAY];
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stop() public onlyOwner {
        _stopped = true;
    }

    function start() public onlyOwner {
        _stopped = false;
    }

    /*
        deploy create a pool
    */
    function deploy(uint256 begin, uint256 duration, uint16 rewardRate, address dexchange, address top) public payable onlyOwner nonReentrant stoppable {
        uint256 value = msg.value;

        require(value > 0, 'DexIDOPool::deploy: require sending DEX to the pool');

        require(begin >= block.timestamp, 'DexIDOPool::deploy: start time is too soon');

        require(duration > 0, 'DexIDOPool::deploy: duration is too short');
        
        require(
            rewardRate < 1000,
            "DexIDOPool::deploy: reward rate use permil"
        );

        require(
            dexchange.isContract(), 
            "DexIDOPool::deploy: dexchangeCore is non-contract."
        );

        require(
            top != address(0),
            "DexIDOPool::deploy: top referrer address is invalid"
        );

        uint256 totalAmount = value;

        //Calculate the daily exchangeable amount，limitPerDay = value / duration(days)
        uint256 limitPerDay = totalAmount.div(duration.div(1 days));

        IDOPool memory pool = IDOPool({
            start: begin,
            duration: duration,
            totalAmount: totalAmount,
            limitPerDay: limitPerDay,
            rewardRate: rewardRate,
            top: top,
            creator: msg.sender
        });

        //Record pool information
        _poolInfo = pool;
        _dexchangeAddr = dexchange;

        emit Deployed(begin, duration, totalAmount, limitPerDay, rewardRate, msg.sender, dexchange, top);
    }

    /*
        deposit DEX to the pool
    */
    function deposit() public payable nonReentrant stoppable {
        uint256 value = msg.value;
        require(value > 0, 'DexIDOPool::deposit: require sending DEX to the pool');

        IDOPool storage pool = _poolInfo;

        //Check if the pool has started
        require(block.timestamp >= pool.start, 'DexIDOPool::deposit: the pool not ready.');

        //Check if the pool is over
        require(block.timestamp <= (pool.start + pool.duration), 'DexIDOPool::deposit: the pool already ended.');

        if (pool.top != msg.sender) {
            address inviter = _invitations[msg.sender];
            require(
                inviter != address(0),
                "DexIDOPool::deposit: you must have a referrer"
            );
        }

        //Calculate the current time belongs to the first few days of the start of the pool
        uint256 TODAY = (block.timestamp - pool.start) / 1 days;

        uint256 total = _totalDepositOf;
        _totalDepositOf = total.add(value);

        uint256 _balance = _balanceOf[msg.sender];
        _balanceOf[msg.sender] = _balance.add(value);

        uint256 dailyDeposit = _dailyDeposit[TODAY];
        _dailyDeposit[TODAY] = dailyDeposit.add(value);

        uint256 dailyDepositOf = _dailyDepositOf[TODAY][msg.sender];
        _dailyDepositOf[TODAY][msg.sender] = dailyDepositOf.add(value);

        emit Deposited(msg.sender, value);
    }

    /*
        withdraw DEX from the pool, the amount deposited today can be withdrawn, 
        or withdraw all after the pool is over.
    */
    function withdraw(uint256 amount) public nonReentrant stoppable returns (bool) {
        IDOPool storage pool = _poolInfo;

        //Check if the pool has started
        require(block.timestamp >= pool.start, 'DexIDOPool::withdraw: the pool not ready.');

        uint256 total = _totalDepositOf;

        // pool is not over.
        if (block.timestamp < (pool.start + pool.duration)) {
            require(amount > 0, 'DexIDOPool::withdraw: the pool is not over, amount is invalid.');

            uint256 TODAY = (block.timestamp - pool.start) / 1 days;
            uint256 todayDeposit = _dailyDepositOf[TODAY][msg.sender];

            require(todayDeposit >= amount, 'DexIDOPool::withdraw: the amount deposited today is not enough.');

            _totalDepositOf = total.sub(amount);

            _balanceOf[msg.sender] = _balanceOf[msg.sender].sub(amount);

            _dailyDepositOf[TODAY][msg.sender] = todayDeposit.sub(amount);
            _dailyDeposit[TODAY] = _dailyDeposit[TODAY].sub(amount);

            // transfer DEX to the address
            msg.sender.transfer(amount);
            emit Withdrawn(msg.sender, amount);

            return true;
        }

        // the pool is OVER.

        uint256 withdrawAmount = _balanceOf[msg.sender];

        // Check whether the contract balance is sufficient
        require(address(this).balance >= withdrawAmount, 'DexIDOPool::withdraw: the pool DEX balance is not enough.');

        _totalDepositOf = total.sub(withdrawAmount);
        // balance of the address deposited
        _balanceOf[msg.sender] = 0;

        // transfer DEX to the address
        msg.sender.transfer(withdrawAmount);
        emit Withdrawn(msg.sender, withdrawAmount);

        return true;
    }

    /*
        transfer token to recipient
    */
    function transfer(address token, address recipient, uint256 amount) public onlyOwner stoppable returns (bool) {
       require(
            token.isContract(), 
            "DexIDOPool::transfer: call to non-contract."
        );
        require(
            recipient != address(0),
            "DexIDOPool::transfer: recipient is invalid."
        );
        require(
            amount > 0,
            "DexIDOPool::transfer: input amount is invalid."
        );
        
        IERC20 tokenContract = IERC20(token);

        require(
            tokenContract.balanceOf(address(this)) >= amount,
            "DexIDOPool::transfer: token balance is insufficient"
        );

        tokenContract.safeTransfer(recipient, amount);

        return true;
    }

    /*
        refund DEX to recipient
    */
    function refund(address payable recipient, uint256 amount) public onlyOwner stoppable returns (bool) {
       
        require(
            recipient != address(0),
            "DexIDOPool::refund: recipient is invalid."
        );
        require(
            amount > 0,
            "DexIDOPool::refund: input amount is invalid."
        );
        
        require(
            address(this).balance >= amount,
            "DexIDOPool::refund: balance is insufficient"
        );

        recipient.transfer(amount);

        return true;
    }

    /*
        Account accept invitation from referrer. 
    */
    function accept(address referrer) public stoppable {
        // require referrer has deposited.
        require(
            _balanceOf[referrer] > 0,
            "DexIDOPool::accept: referrer did not deposit DEX"
        );

        require(
            _invitations[msg.sender] == address(0),
            "DexIDOPool::accept: has been accepted invitation"
        );

        _invitations[msg.sender] = referrer;
    }
    
    /*
        buy DEX, sending token to exchange
    */
    function buy(address token, uint256 amount) public nonReentrant stoppable {
        
        IDOPool storage pool = _poolInfo;

        //Check if the pool has started
        require(block.timestamp >= pool.start, 'DexIDOPool::buy: the pool not ready.');

        //Check if the pool is over
        require(block.timestamp <= (pool.start + pool.duration), 'DexIDOPool::buy: the pool already ended.');

        require(
            token.isContract(), 
            "DexIDOPool::buy: call to non-contract."
        );

        require(
            amount > 0,
            "DexIDOPool::buy: input amount is invalid."
        );

        DexchangeCore dexchangeCore = DexchangeCore(_dexchangeAddr);

        uint256 _price = dexchangeCore.price(token);

        require(
            _price > 0,
            "DexIDOPool::buy: do not support the token."
        );

        IERC20 tokenContract = IERC20(token);

        uint256 totalAmount = amount.mul(_price).div(10**18);

        require(
            tokenContract.balanceOf(msg.sender) >= totalAmount,
            "DexIDOPool::buy: token balance is insufficient"
        );
        require(
            tokenContract.allowance(msg.sender, address(this)) >= totalAmount,
            "DexIDOPool::buy: token allowance is insufficient"
        );

        // fetch available DEX amount, and subtract the bought amount
        uint256 available = this.availableToExchange(msg.sender);
        uint256 TODAY = (block.timestamp - pool.start) / 1 days;
        uint256 today = _dailyExchange[TODAY][msg.sender];

        require(
            available.sub(today) >= amount,
            "DexIDOPool::buy: amount exceeds the available amount"
        );

        // calculate the referral rewards
        uint256 rewards = amount.mul(pool.rewardRate).div(1000);
        address inviter1 = _invitations[msg.sender];
        
        require(
            inviter1 != address(0),
            "DexIDOPool::buy: you must have a referrer"
        );

        // send token to Contract
        tokenContract.safeTransferFrom(msg.sender, address(this), totalAmount);

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
                // 2nd level referrer
                inviter3 = _invitations[inviter2];
                if (inviter3 != address(0)) {
                    // 3rd level referrer
                    inviter4 = _invitations[inviter3];
                    // 4th level referrer
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
    
        _totalExchange = _totalExchange.add(amount);

        _dailyExchange[TODAY][msg.sender] = today.add(amount);

        // send DEX to sender, subtract rewards
        msg.sender.transfer(amount.sub(rewards));

        emit Bought(msg.sender, amount, token, _price);
    }

}
