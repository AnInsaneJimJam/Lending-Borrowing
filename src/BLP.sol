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

    IERC20 public immutable wETH;
    IERC20 public immutable USDT;
    address public addressOfWeth;
    address public addressOfUsdt;

    mapping(address user => uint256 amount) amountDepositedBy;

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
    function depositUSDT(address token, uint256 amount) public validDepositToken(token) moreThanZero(amount) {
        USDT.transferFrom(msg.sender, address(this), amount);
        amountDepositedBy[msg.sender] += amount;
        emit BLP_USDT_Deposited(amount);
    }

    /////////////// Internal functions /////////////

    ////////////// Getter Functions /////////////

}