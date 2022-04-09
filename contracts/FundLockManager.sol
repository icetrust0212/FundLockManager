// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// use safe math to prevent underflow and overflow
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./interface/IUniswapFactory.sol";
import "./interface/IUniswapRouter.sol";

contract FundLockManager is Ownable, ReentrancyGuard {

    // calling SafeMath will add extra functions to the uint data type
    using SafeMath for uint; // you can make a call like myUint.add(123)
    using Counters for Counters.Counter;
    //Plan structure
    struct Plan {
        uint id;
        address owner;
        address unlocker;
        uint amount;
        bool isToken;
        uint lockTime;
        bool isClaimable;
    }

    ERC20 public _denominationToken;

    // plans per address
    Plan[] public _plans;
    Counters.Counter _planCounter;

    //uniswap
    IUniswapV2Factory public _uniswapV2Factory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    IUniswapV2Router02 public _uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    event NewPlanCreated (
        uint id,
        address indexed owner,
        address indexed to,
        bool isToken,
        uint amount,
        uint lockTime
    );

    
    constructor(address erc20Token) {
        _denominationToken = ERC20(erc20Token);
    }

    /**
        @dev Sender will send eth to this, and swap it with denomination ERC20 token on uniswap, and create lock funds
        @param unlocker The address that will be able to unlock the funds within lock time
        @param lockTime lock time
    */
    function LockEthWithSwapToken(address unlocker, uint lockTime) external payable {
        require(msg.value > 0, "Eth amount should be great zero");
        require(unlocker != address(0), "unlocker cannot be zero");
        require(lockTime > 0, "LockTime is too short");

        //do swap with token
        uint amount = swapEthForToken();

        //create lock funds
        createNewERC20Plan(amount, unlocker, lockTime);
    }

   
    /**
        @dev Sender swaps any ERC20 token with Eth on uniswap, and create lock funds
        @param erc20Token Any ERC20 token for swap
        @param unlocker The address that will be able to unlock the funds within lock time
        @param amount ERC20 token amount
        @param lockTime lock time
    */
    function LockTokenWithSwapEth(address erc20Token, uint amount, address unlocker, uint lockTime) external {
        require(amount > 0, "Eth amount should be great zero");
        require(unlocker != address(0), "unlocker cannot be zero");
        require(lockTime > 0, "LockTime is too short");
        require(ERC20(erc20Token).allowance(msg.sender, address(_uniswapV2Router)) >= amount, "Allowance is not enough.");

        //do swap with token
        uint ethAmount = swapTokenForEth(erc20Token, amount);

        //create lock funds
        createNewEthPlan(ethAmount, unlocker, lockTime);
    }

   /**
        @dev Sender swaps any ERC20 token with denomination ERC20 token on uniswap, and create lock funds
        @param erc20Token Any ERC20 token for swap
        @param unlocker The address that will be able to unlock the funds within lock time
        @param amount ERC20 token amount
        @param lockTime lock time
    */
    function LockTokenWithSwapToken(address erc20Token, uint amount, address unlocker, uint lockTime) external {
        require(amount > 0, "Eth amount should be great zero");
        require(unlocker != address(0), "unlocker cannot be zero");
        require(lockTime > 0, "LockTime is too short");
        require(erc20Token != address(_denominationToken), "Same token.");
        require(ERC20(erc20Token).allowance(msg.sender, address(_uniswapV2Router)) >= amount, "Allowance is not enough.");

        //do swap with token
        uint tokenAmount = swapTokenForToken(erc20Token, amount);

        //create lock funds
        createNewERC20Plan(tokenAmount, unlocker, lockTime);
    }

    /**
        @dev Sender deposite eth directly
        @param unlocker The address that will be able to unlock the funds within lock time
        @param lockTime lock time
    */
    function LockEth( address unlocker, uint lockTime) external payable {
        require(msg.value > 0, "Eth amount should be great zero");
        require(unlocker != address(0), "unlocker cannot be zero");
        require(lockTime > 0, "LockTime is too short");

        //create lock funds
        createNewEthPlan(msg.value, unlocker, lockTime);
    }

    /**
        @dev Sender deposite denomination ERC20 token directly
        @param amount The amount of denomination ERC20 token
        @param unlocker The address that will be able to unlock the funds within lock time
        @param lockTime lock time
    */
    function LockToken(uint amount, address unlocker, uint lockTime) external {
        require(unlocker != address(0), "unlocker cannot be zero");
        require(lockTime > 0, "LockTime is too short");
        require(ERC20(_denominationToken).allowance(msg.sender, address(this)) >= amount, "Allowance is not enough.");

        //create lock funds
        createNewERC20Plan(amount, unlocker, lockTime);
    }

    /**
    @dev Swap erc20 token with Eth
    @param tokenAmount token amount for swap.
    @param erc20Token Allowed ERC20 token for swap
    */

    function swapTokenForEth(address erc20Token, uint256 tokenAmount) private returns (uint) {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = erc20Token;
        path[1] = _uniswapV2Router.WETH();

        uint originBalance = address(this).balance;
        // make the swap
        _uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
        uint currentBalance = address(this).balance;

        return currentBalance.sub(originBalance);
    }

    /**
    @dev Swap erc20 token with Eth
    */

    function swapEthForToken() private returns (uint) {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = _uniswapV2Router.WETH();
        path[1] = address(_denominationToken);

        uint originBalance = _denominationToken.balanceOf(address(this));
        // make the swap
        _uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: msg.value}(
            0,
            path,
            address(this),
            block.timestamp
        );
        uint currentBalance = _denominationToken.balanceOf(address(this));
        return currentBalance.sub(originBalance);
    }

     /**
    @dev Swap erc20 token with denomination ERC20 token
    @param tokenAmount token amount for swap.
    @param erc20Token Allowed ERC20 token for swap
    */

    function swapTokenForToken(address erc20Token, uint256 tokenAmount) private returns(uint) {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = erc20Token;
        path[1] = address(_denominationToken);

        uint originBalance = _denominationToken.balanceOf(address(this));

        // make the swap
        _uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
        uint currentBalance = _denominationToken.balanceOf(address(this));

        return currentBalance.sub(originBalance);
    }

    
    /** 
        @dev Create New Eth plan.
        @param amount eth amount to be locked
        @param unlocker: address that has right to unlock fund in locktime.
        @param lockTime: lock time
    **/ 

    function createNewEthPlan(uint amount, address unlocker, uint256 lockTime) internal {

        Plan memory _newPlan = Plan({
            id: _planCounter.current(),
            owner: msg.sender,
            unlocker: unlocker,
            amount: amount,
            isToken: false,
            lockTime: block.timestamp + lockTime,
            isClaimable: true
        });

        _plans.push(_newPlan);
        emit NewPlanCreated(_planCounter.current(), msg.sender, unlocker, false, amount, lockTime);

        _planCounter.increment();
    }

    /** 
        @dev Create New ERC20 plan.
        @param amount: Token amount
        @param unlocker: address that has right to unlock fund in locktime.
        @param lockTime: lock time
    **/ 

    function createNewERC20Plan( uint256 amount, address unlocker, uint256 lockTime) internal {
        Plan memory _newPlan = Plan({
            id: _planCounter.current(),
            owner: msg.sender,
            unlocker: unlocker,
            amount: amount,
            isToken: true,
            lockTime: block.timestamp + lockTime,
            isClaimable: true
        });

        _plans.push(_newPlan);

        emit NewPlanCreated(_planCounter.current(), msg.sender, unlocker, true, amount, lockTime);
        _planCounter.increment();
    }

    /** 
        @dev Get all plans per owner
        @param owner owner of plans
    **/

    function getPlansByOwner(address owner) external view returns(Plan[] memory) {
        Plan[] memory plans = new Plan[](_plans.length);
        uint counter = 0;
        for (uint i = 0 ; i < _plans.length ; i ++ ) {
            Plan memory plan = _plans[i];
            if (plan.owner == owner) {
                plans[counter] = plan;
                counter ++;
            }
        }
        return plans;
    }

    /**
        @dev Get certain plan per owner already expired.
        @param unlocker unlocker of plan
     */

    function getPlansByUnlocker(address unlocker) external view returns(Plan[] memory) {
        Plan[] memory plans = new Plan[](_plans.length);
        uint counter = 0;
        for (uint i = 0 ; i < _plans.length ; i ++ ) {
            Plan memory plan = _plans[i];
            if (plan.unlocker == unlocker && block.timestamp > plan.lockTime && plan.isClaimable) {
                plans[counter] = plan;
                counter ++;
            }
        }
        return plans;
    }


    /**
        @dev claim locked token within lock time  -  unlocker.
        @param id locked fund id
     */

     function claimLockedFund(uint id) external nonReentrant {
        require(id <= _planCounter.current(), "Fund not exist.");
        Plan storage plan = _plans[id];

        require(plan.unlocker == msg.sender, "You are not unlocker.");
        require(plan.lockTime < block.timestamp, "Fund expired.");
        require(plan.isClaimable, "Fund already claimed.");

        plan.isClaimable = false;


        if (plan.isToken) {
            _denominationToken.transfer(msg.sender, plan.amount);
        } else {
             (bool sent, bytes memory data) = msg.sender.call{value: plan.amount}("");
            require(sent, "Failed to send Ether");
        }

     }

     /**
        @dev Withdraw money back within lockTime. Owner, 
        @param id plan id
      */

      function withdraw(uint id) external nonReentrant {
        require(id <= _planCounter.current(), "Fund not exist.");
        Plan storage plan = _plans[id];

        require(plan.owner == msg.sender, "You are not owner.");
        require(plan.lockTime < block.timestamp, "Fund not expired.");
        require(plan.isClaimable, "Fund already claimed.");

        plan.isClaimable = false;

        if (plan.isToken) {
            _denominationToken.transfer(msg.sender, plan.amount);
        } else {
             (bool sent, bytes memory data) = msg.sender.call{value: plan.amount}("");
            require(sent, "Failed to send Ether");
        }
        
      }

}