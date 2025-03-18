# A Basic Borrowing and Lending Protocol
1. wETH as Collateral and get USDT as loan
    -Assumes USDT = 1 $ or can take from price feed
2. A fixed 8% interest rate for borrowing and 3% for lending
3. Lenders can deposit USDT and withdraw as long as liquidity is there
4. Main issue is to check whether a person's position can be liquidated considered interest and latest price of collateral automatically
5. Collateral should be atleast 150% of borrowed amount.

