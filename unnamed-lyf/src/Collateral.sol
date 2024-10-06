// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;
import "./PoolToken.sol";
import "./CStorage.sol";
import "./CSetter.sol";
import "./interfaces/IBorrowable.sol";
import "./interfaces/ICollateral.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/ILyfPriceOracle.sol";
import "./interfaces/ILyfCallee.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./libraries/UQ112x112.sol";
import "./libraries/Math.sol";

error PriceCalculationError();
contract Collateral is ICollateral, PoolToken, CStorage, CSetter {
    using UQ112x112 for uint224;
    constructor() public {}
    /*** Collateralization Model ***/
    // returns the prices of borrowable0's and borrowable1's underlyings with collateral's underlying as denom
    function getPrices() public returns (uint256 price0, uint256 price1) {
        (uint224 twapPrice112x112, ) = ILyfPriceOracle(lyfPriceOracle)
            .getResult(underlying);
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(underlying)
            .getReserves();
        uint256 collateralTotalSupply = IUniswapV2Pair(underlying)
            .totalSupply();
        uint224 currentPrice112x112 = UQ112x112.encode(reserve1).uqdiv(
            reserve0
        );
        uint256 adjustmentSquared = (uint256(twapPrice112x112) * (2 ** 32)) /
            (currentPrice112x112);
        uint256 adjustment = Math.sqrt(adjustmentSquared * (2 ** 32));
        uint256 currentBorrowable0Price = (uint256(collateralTotalSupply) *
            (1e18)) / (reserve0 * 2);
        uint256 currentBorrowable1Price = (uint256(collateralTotalSupply) *
            (1e18)) / (reserve1 * 2);
        price0 = (currentBorrowable0Price * (adjustment)) / (2 ** 32);
        price1 = (currentBorrowable1Price * (2 ** 32)) / (adjustment);
        /*
         * Price calculation errors may happen in some edge pairs where
         * reserve0 / reserve1 is close to 2**112 or 1/2**112
         * We're going to prevent users from using pairs at risk from the UI
         */
        require(price0 > 100, "Lyf: PRICE_CALCULATION_ERROR");
        require(price1 > 100, "Lyf: PRICE_CALCULATION_ERROR");
    }
    // returns liquidity in  collateral's underlying
    function _calculateLiquidity(
        uint256 amountCollateral,
        uint256 amount0,
        uint256 amount1
    ) internal returns (uint256 liquidity, uint256 shortfall) {
        uint256 _safetyMarginSqrt = safetyMarginSqrt;
        (uint256 price0, uint256 price1) = getPrices();
        uint256 a = (amount0 * (price0)) / (1e18);
        uint256 b = (amount1 * (price1)) / (1e18);
        if (a < b) (a, b) = (b, a);
        a = (a * (_safetyMarginSqrt)) / (1e18);
        b = (b * (1e18)) / (_safetyMarginSqrt);
        uint256 collateralNeeded = a + ((b) * (liquidationIncentive)) / (1e18);
        if (amountCollateral >= collateralNeeded) {
            return (amountCollateral - collateralNeeded, 0);
        } else {
            return (0, collateralNeeded - amountCollateral);
        }
    }
    /*** ERC20 ***/
    function _transfer(address from, address to, uint256 value) internal {
        require(tokensUnlocked(from, value), "Lyf: INSUFFICIENT_LIQUIDITY");
        super._transfer(from, to, value);
    }
    function tokensUnlocked(address from, uint256 value) public returns (bool) {
        uint256 _balance = balanceOf[from];
        if (value > _balance) return false;
        uint256 finalBalance = _balance - value;
        uint256 amountCollateral = (finalBalance * (exchangeRate())) / (1e18);
        uint256 amount0 = IBorrowable(borrowable0).borrowBalance(from);
        uint256 amount1 = IBorrowable(borrowable1).borrowBalance(from);
        (, uint256 shortfall) = _calculateLiquidity(
            amountCollateral,
            amount0,
            amount1
        );
        return shortfall == 0;
    }
    /*** Collateral ***/
    function accountLiquidityAmounts(
        address borrower,
        uint256 amount0,
        uint256 amount1
    ) public returns (uint256 liquidity, uint256 shortfall) {
        if (amount0 == uint256(-1))
            amount0 = IBorrowable(borrowable0).borrowBalance(borrower);
        if (amount1 == uint256(-1))
            amount1 = IBorrowable(borrowable1).borrowBalance(borrower);
        uint256 amountCollateral = (balanceOf[borrower] * (exchangeRate())) /
            (1e18);
        return _calculateLiquidity(amountCollateral, amount0, amount1);
    }
    function accountLiquidity(
        address borrower
    ) public returns (uint256 liquidity, uint256 shortfall) {
        return accountLiquidityAmounts(borrower, uint256(-1), uint256(-1));
    }
    function canBorrow(
        address borrower,
        address borrowable,
        uint256 accountBorrows
    ) public returns (bool) {
        address _borrowable0 = borrowable0;
        address _borrowable1 = borrowable1;
        require(
            borrowable == _borrowable0 || borrowable == _borrowable1,
            "Lyf: INVALID_BORROWABLE"
        );
        uint256 amount0 = borrowable == _borrowable0
            ? accountBorrows
            : uint256(-1);
        uint256 amount1 = borrowable == _borrowable1
            ? accountBorrows
            : uint256(-1);
        (, uint256 shortfall) = accountLiquidityAmounts(
            borrower,
            amount0,
            amount1
        );
        return shortfall == 0;
    }
    // this function must be called from borrowable0 or borrowable1
    function seize(
        address liquidator,
        address borrower,
        uint256 repayAmount
    ) external returns (uint256 seizeTokens) {
        require(
            msg.sender == borrowable0 || msg.sender == borrowable1,
            "Lyf: UNAUTHORIZED"
        );
        (, uint256 shortfall) = accountLiquidity(borrower);
        require(shortfall > 0, "Lyf: INSUFFICIENT_SHORTFALL");
        uint256 price;
        if (msg.sender == borrowable0) (price, ) = getPrices();
        else (, price) = getPrices();
        seizeTokens =
            (((repayAmount * (liquidationIncentive)) / (1e18)) * (price)) /
            (exchangeRate());
        balanceOf[borrower] =
            balanceOf[borrower] -
            (seizeTokens, "Lyf: LIQUIDATING_TOO_MUCH");
        balanceOf[liquidator] = balanceOf[liquidator] + (seizeTokens);
        emit Transfer(borrower, liquidator, seizeTokens);
    }
    // this low-level function should be called from another contract
    function flashRedeem(
        address redeemer,
        uint256 redeemAmount,
        bytes calldata data
    ) external nonReentrant update {
        require(redeemAmount <= totalBalance, "Lyf: INSUFFICIENT_CASH");
        // optimistically transfer funds
        _safeTransfer(redeemer, redeemAmount);
        if (data.length > 0)
            ILyfCallee(redeemer).lyfRedeem(msg.sender, redeemAmount, data);
        uint256 redeemTokens = balanceOf[address(this)];
        uint256 declaredRedeemTokens = (redeemAmount * (1e18)) /
            (exchangeRate()) +
            (1); // rounded up
        require(
            redeemTokens >= declaredRedeemTokens,
            "Lyf: INSUFFICIENT_REDEEM_TOKENS"
        );
        _burn(address(this), redeemTokens);
        emit Redeem(msg.sender, redeemer, redeemAmount, redeemTokens);
    }
}
