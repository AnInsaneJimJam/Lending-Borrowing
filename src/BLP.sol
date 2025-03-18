//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title A simple Borrow Lending Protocol
 * @author Anand Bansal
 * @notice This is a simple BLP with fixed borrowing and lending 
 */
contract BLP is ReentrancyGuard {

    uint256 public constant INTEREST_RATE = 8 ;
    uint256 public constant SECONDS_IN_YEAR = 31536000;

    IERC20 public immutable wETH;
    IERC20 public immutable USDT;
    address public addressOfWeth;
    address public addressOfUsdt;

    struct Deposit {
    uint256 amount;
    uint256 timestamp;}

    mapping(address => Deposit[]) public userDeposits;

    ////////////// Event ////////////////
    event BLP_USDT_Deposited(uint256 indexed amount);

    ////////////// Error ////////////////
    error BLP__InvalidDepositTokenAddress(address token);
    error BLP__InvalidCollateralTokenAddress(address token);
    error BLP__AmountMustBeMoreThanZero();

    constructor(address _weth, address _usdt){
        wETH = IERC20(_weth);
        USDT =IERC20(_usdt);
        addressOfWeth = _weth;
        addressOfUsdt = _usdt;
    }

    ////////////////// Modifiers //////////////////
    modifier validDepositToken(address token){
        require(token == addressOfUsdt, BLP__InvalidDepositTokenAddress(token));
        _;

    }

    modifier validCollateralToken(address token){
        require(token == addressOfWeth, BLP__InvalidCollateralTokenAddress(token));
        _;
    }

    modifier moreThanZero(uint256 amount){
        require(amount > 0, BLP__AmountMustBeMoreThanZero());
        _;
    }

    ////////////////  Public functions //////////////
    function provideUSDTForLiquidity(address token, uint256 amount) public validDepositToken(token) moreThanZero(amount) {
        USDT.transferFrom(msg.sender, address(this), amount);
        userDeposits[msg.sender].push(Deposit(amount, block.timestamp));
        emit BLP_USDT_Deposited(amount);
    }

    function withdrawLiquidityInUsd(uint256 amount) public{}

    /////////////// Internal functions /////////////

    function _getTotalValueOfDeposit() internal returns(uint256 totalAmount){
        uint256 interest ;
        uint256 length = getDeposits(msg.sender).length;
        for(uint256 i =0 ; i < length ; i++){
            uint256 amount = getDeposits(msg.sender)[i].amount;
            uint256 timestamp = getDeposits(msg.sender)[i].timestamp;
            uint256 timeElapsed = block.timestamp - timestamp;
            interest += (amount * timeElapsed * INTEREST_RATE)/SECONDS_IN_YEAR;
            totalAmount += amount + interest;
        }
    }

    ////////////// Getter Functions ///////////////

    function getDeposits(address user) public returns ( Deposit[] memory){
        return userDeposits[user];
    }
}