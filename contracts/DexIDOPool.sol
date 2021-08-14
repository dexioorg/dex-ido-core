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

contract DexIDOPool is ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    struct IDOPool {
        uint256 start; // IDO pool starting time
        uint256 duration; // IDO pool duration
        uint256 totalAmount; // Total DEX amount of the pool
        uint256 limitPerDay; // Daily exchange limit
        address creator; // IDO pool creator
    }

    // Stop contract function
    bool private _stopped;
    // Pool info
    IDOPool private _poolInfo;
    // Total deposited amount of the pool
    uint256 private _totalDepositOf;
    // Deposited amount of the address in the pool
    mapping(address => uint256) private _balanceOf;
    // Daily deposited amount of the pool
    mapping(uint256 => uint256) private _dailyDeposit;
    // Daily deposited amount of the address in the pool
    mapping(uint256 => mapping(address => uint256)) private _dailyDepositOf;

    /* ========== EVENTS ========== */

    event Deployed(
        uint256 start,
        uint256 duration,
        uint256 totalAmount,
        uint256 limitPerDay,
        address creator
    );
    event Deposited(address sender, uint256 amount);
    event Withdrawn(address sender, uint256 amount);

    /* ========== CONSTRUCTOR ========== */

    constructor() public Ownable() {}

    /* ========== MODIFIERS ========== */

    modifier stoppable {
        require(!_stopped, 'DexIDOPool::stoppable: contract has been stopped.');
        _;
    }

    /* ========== VIEWS ========== */

    function stopped() public view returns (bool) {
        return _stopped;
    }
    
    function totalDeposit() public view returns (uint256) {
        return _totalDepositOf;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balanceOf[account];
    }

    function availableToExchange(address account) public view returns (uint256) {
        IDOPool storage info = _poolInfo;

        if(info.start > block.timestamp) {
            return 0;
        }
        if(block.timestamp > (info.start + info.duration)) {
            return 0;
        }

        uint256 TODAY = (block.timestamp - info.start) / 1 days;
        uint256 balance = _balanceOf[account] - _dailyDepositOf[TODAY][account];
        uint256 total = _totalDepositOf - _dailyDeposit[TODAY];
        if (_totalDepositOf == _dailyDeposit[TODAY]) {
            return 0;
        }

        uint256 available = balance.mul(info.limitPerDay).div(total);

        return available;
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
    function deploy(
        uint256 begin,
        uint256 duration
    ) public payable onlyOwner nonReentrant stoppable {

        uint256 value = msg.value;

        require(value > 0, 'DexIDOPool::deploy: require sending DEX to the pool');

        require(begin >= block.timestamp, 'DexIDOPool::deploy: start time is too soon');

        require(duration > 0, 'DexIDOPool::deploy: duration is too short');
        
        uint256 totalAmount = value;

        //Calculate the daily exchangeable amount，limitPerDay = value / duration(days)
        uint256 limitPerDay = totalAmount.div(duration.div(1 days));

        IDOPool memory pool =
            IDOPool({
                start: begin,
                duration: duration,
                totalAmount: totalAmount,
                limitPerDay: limitPerDay,
                creator: msg.sender
            });

        //Record pool information
        _poolInfo = pool;

        emit Deployed(begin, duration, totalAmount, limitPerDay, msg.sender);
    }

    /*
        deposit DEX to the pool
    */
    function deposit() public payable nonReentrant stoppable {

        uint256 value = msg.value;
        require(value > 0, 'DexIDOPool::deposit: require sending DEX to the pool');

        IDOPool storage info = _poolInfo;

        //Check if the pool has started
        require(block.timestamp >= info.start, 'DexIDOPool::deposit: the pool not ready.');

        //Check if the pool is over
        require(block.timestamp <= (info.start + info.duration), 'DexIDOPool::deposit: the pool already ended.');

        //Calculate the current time belongs to the first few days of the start of the pool
        uint256 TODAY = (block.timestamp - info.start) / 1 days;

        uint256 total = _totalDepositOf;
        _totalDepositOf = total + value;

        uint256 _balance = _balanceOf[msg.sender];
        _balanceOf[msg.sender] = _balance + value;

        uint256 dailyDeposit = _dailyDeposit[TODAY];
        _dailyDeposit[TODAY] = dailyDeposit + value;

        uint256 dailyDepositOf = _dailyDepositOf[TODAY][msg.sender];
        _dailyDepositOf[TODAY][msg.sender] = dailyDepositOf + value;

        emit Deposited(msg.sender, value);
    }

    /*
        withdraw DEX from the pool, the amount deposited today can be withdrawn, 
        or withdraw all after the pool is over.
    */
    function withdraw(uint256 amount) public nonReentrant stoppable returns (bool) {
        IDOPool storage info = _poolInfo;

        //Check if the pool has started
        require(block.timestamp >= info.start, 'DexIDOPool::withdraw: the pool not ready.');

        uint256 total = _totalDepositOf;

        // pool is not over.
        if (block.timestamp < (info.start + info.duration)) {
            
            require(
                amount > 0, 
                'DexIDOPool::withdraw: the pool is not over, amount is invalid.'
            );

            uint256 TODAY = (block.timestamp - info.start) / 1 days;
            uint256 todayDeposit = _dailyDepositOf[TODAY][msg.sender];
            
            require(
                todayDeposit >= amount,
                'DexIDOPool::withdraw: the amount deposited today is not enough.'
            );

            _totalDepositOf = total - amount;

            uint256 _balance = _balanceOf[msg.sender];
            _balanceOf[msg.sender] = _balance - amount;
            
            _dailyDepositOf[TODAY][msg.sender] = todayDeposit - amount;
            _dailyDeposit[TODAY] = _dailyDeposit[TODAY] - amount;

            // transfer DEX to the address
            msg.sender.transfer(amount);
            emit Withdrawn(msg.sender, amount);

            return true;
        }

        // the pool is OVER.
        
        uint256 withdrawAmount = _balanceOf[msg.sender];

        // Check whether the contract balance is sufficient
        require(
            address(this).balance >= withdrawAmount,
            'DexIDOPool::withdraw: the pool DEX balance is not enough.'
        );

        _totalDepositOf = total - withdrawAmount;
        // balance of the address deposited
        _balanceOf[msg.sender] = 0;

        // transfer DEX to the address
        msg.sender.transfer(withdrawAmount);
        emit Withdrawn(msg.sender, withdrawAmount);

        return true;
    }
}
