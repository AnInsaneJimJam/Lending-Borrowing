//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title A simple Borrow Lending Protocol
 * @author Anand Bansal
 * @notice This is a simple BLP with fixed borrowing and lending interest rate
 * @notice Collateral will be wETH and lending and borrowing unit will be USDT
 * @notice Liquidate function
 */
contract BLP is ReentrancyGuard {
    uint256 private constant INTEREST_RATE = 8;
    uint256 private constant SECONDS_IN_YEAR = 31536000;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;

    IERC20 public immutable wETH;
    IERC20 public immutable USDT;
    address public addressOfWeth;
    address public addressOfUsdt;

    struct Deposit {
        uint256 amount;
        uint256 timestamp;
    }

    struct Debt {
        uint256 usdtBorrowed;
        uint256 timestamp;
    }

    mapping(address => Deposit[]) public userDeposits;
    address wethPriceFeed; 
    address usdtPriceFeed; 
    mapping(address user =>  uint256 amount) public collateralDeposited;
    mapping(address user => Debt[]) public userDebt;

    ////////////// Event ////////////////
    event BLP_USDT_Deposited(uint256 indexed amount);
    event BLP__USDT_Withdrawn(uint256 indexed amount);
    event BLP__WETH_Deposited(uint256 indexed amount);
    event BLP__WETH_Withdrawn(uint256 indexed amount);
    event BLP__USDT_Borrowed(uint256 indexed amount);

    ////////////// Error ////////////////
    error BLP__InvalidDepositTokenAddress(address token);
    error BLP__InvalidCollateralTokenAddress(address token);
    error BLP__AmountMustBeMoreThanZero();
    error BLP__InsufficentDepositToWithdraw();
    error BLP__LowCollaterizationRatio();
    error BLP__InsufficientLiquidity();
    
    ///////////// Constructor ////////////
    error BLP__InsufficentCollateralToWithdraw();
    constructor(address _weth, address _usdt, address _wethPriceFeeed, address _usdtPriceFeed) {
        wETH = IERC20(_weth);
        USDT = IERC20(_usdt);
        addressOfWeth = _weth;
        addressOfUsdt = _usdt;
        wethPriceFeed = _wethPriceFeeed;
        usdtPriceFeed = _usdtPriceFeed;
    }

    ////////////////// Modifiers //////////////////
    modifier validDepositToken(address token) {
        require(token == addressOfUsdt, BLP__InvalidDepositTokenAddress(token));
        _;
    }

    modifier validCollateralToken(address token) {
        require(token == addressOfWeth, BLP__InvalidCollateralTokenAddress(token));
        _;
    }

    modifier moreThanZero(uint256 amount) {
        require(amount > 0, BLP__AmountMustBeMoreThanZero());
        _;
    }

    ////////////////  Public functions //////////////
    function provideUSDTForLiquidity(address token, uint256 amount)
        public
        validDepositToken(token)
        moreThanZero(amount)
    {
        USDT.transferFrom(msg.sender, address(this), amount);
        userDeposits[msg.sender].push(Deposit(amount, block.timestamp));
        emit BLP_USDT_Deposited(amount);
    }

    function withdrawLiquidityInUsdt(uint256 amount) public nonReentrant moreThanZero(amount) {
        uint256 totalValue = getTotalValueOfDeposit();
        require(amount <= totalValue, "BLP__InsufficientDepositToWithdraw");

        uint256 remainingAmount = amount;
        Deposit[] storage deposits = userDeposits[msg.sender];
        uint256 length = deposits.length;
        for (uint256 i = 0; i < length; i++) {
            Deposit storage deposit = deposits[i];

            uint256 timeElapsed = block.timestamp - deposit.timestamp;
            uint256 interest = _calulateInterest(deposit.amount, timeElapsed);
            uint256 totalDepositValue = deposit.amount + interest;

            if (totalDepositValue >= remainingAmount) {
                deposit.amount = totalDepositValue - remainingAmount;
                USDT.transfer(msg.sender, remainingAmount);
                remainingAmount = 0;
                break;
            } else {
                remainingAmount -= totalDepositValue;
                USDT.transfer(msg.sender, totalDepositValue);
                deposits[i] = deposits[deposits.length - 1];
                deposits.pop();
                length--; // Adjust the loop length
                i--; // Adjust the fucking loop index
            }
        }
        require(remainingAmount == 0, "BLP__InsufficientDepositToWithdraw"); // sanity check
        emit BLP__USDT_Withdrawn(amount);
    }

    function getTotalValueOfDeposit() public view returns (uint256 totalAmount) {
        uint256 length = getDeposits(msg.sender).length;
        for (uint256 i = 0; i < length; i++) {
            uint256 amount = getDeposits(msg.sender)[i].amount;
            uint256 timestamp = getDeposits(msg.sender)[i].timestamp;
            uint256 timeElapsed = block.timestamp - timestamp;
            uint256 interest = _calulateInterest(amount, timeElapsed);
            totalAmount += amount + interest;
        }
    }

    function depositCollateral (address token, uint256 amount) public moreThanZero(amount) validCollateralToken(token){
        wETH.transferFrom(msg.sender,address(this),amount);
        collateralDeposited[msg.sender] += amount;
        emit BLP__WETH_Deposited(amount);
    }

    function withdrawCollateral (address token, uint256 amount) public moreThanZero(amount) validCollateralToken(token){
        require(collateralDeposited[msg.sender]>amount , BLP__InsufficentCollateralToWithdraw());
        collateralDeposited[msg.sender] -= amount;
        _revertIfColllaterizationRatioIsLow(msg.sender);
        wETH.transfer(msg.sender,amount);
        emit BLP__WETH_Withdrawn(amount);
    }

    function borrowUsdt (address token, uint256 amount) public moreThanZero(amount) validDepositToken(token) nonReentrant{
        userDebt[msg.sender].push(Deposit(amount,block.timestamp));
        _revertIfColllaterizationRatioIsLow(msg.sender);
        require(USDT.balanceOf(address(this))> amount, BLP__InsufficientLiquidity());
        USDT.transfer(msg.sender,amount);
        emit BLP__USDT_Borrowed(amount);
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(token == addressOfUsdt ? usdtPriceFeed : wethPriceFeed);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // 1 ETH = 1000 USD
        // The returned value from Chainlink will be 1000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
    /////////////// Internal functions /////////////

    function _calulateInterest(uint256 amount, uint256 timeElapsed) internal pure returns (uint256 interest) {
        interest += (amount * timeElapsed * INTEREST_RATE) / SECONDS_IN_YEAR;
    }

    //Need to take care of interest on debt now
    function _calculateCollaterizationRatio(address user) internal view returns(uint256 ratio){
        ratio = (getUsdValue(addressOfUsdt,collateralDeposited[user])*1e18)/getUsdValue(addressOfUsdt, UsdtBorrowed[user]);
        //should be greater than 1.5e18
    }

    function _revertIfColllaterizationRatioIsLow(address user) internal view{
        uint256 ratio = _calculateCollaterizationRatio(user);
        // 1.5e18 = 15e17
        require(ratio > 15e17 , BLP__LowCollaterizationRatio());
    }



    ////////////// Getter Functions ///////////////

    function getDeposits(address user) public view returns (Deposit[] memory) {
        return userDeposits[user];
    }
}
