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
import "./ErrorHandler.sol";

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
        uint256 adjustmentSquared = (uint256(twapPrice112x112) * 2 ** 32) /
            (currentPrice112x112);
        uint256 adjustment = Math.sqrt(adjustmentSquared * 2 ** 32);
        uint256 currentBorrowable0Price = (uint256(collateralTotalSupply) *
            1e18) / (reserve0 * 2);
        uint256 currentBorrowable1Price = (uint256(collateralTotalSupply) *
            1e18) / (reserve1 * 2);
        price0 = (currentBorrowable0Price * adjustment) / 2 ** 32;
        price1 = (currentBorrowable1Price * (2 ** 32)) / adjustment;
        /*
         * Price calculation errors may happen in some edge pairs where
         * reserve0 / reserve1 is close to 2**112 or 1/2**112
         * We're going to prevent users from using pairs at risk from the UI
         */
        require(price0 > 100, ErrorHandler.PriceCalculationError());
        require(price1 > 100, ErrorHandler.PriceCalculationError());
    }
    // returns liquidity in  collateral's underlying
    function _calculateLiquidity(
        uint256 amountCollateral,
        uint256 amount0,
        uint256 amount1
    ) internal returns (uint256 liquidity, uint256 shortfall) {
        uint256 _safetyMarginSqrt = safetyMarginSqrt;
        (uint256 price0, uint256 price1) = getPrices();
        uint256 a = (amount0 * price0) / 1e18;
        uint256 b = (amount1 * price1) / 1e18;
        if (a < b) (a, b) = (b, a);
        a = (a * _safetyMarginSqrt) / 1e18;
        b = (b * 1e18) / _safetyMarginSqrt;
        uint256 collateralNeeded = a + ((b * liquidationIncentive) / 1e18);
        return (
            amountCollateral >= collateralNeeded
                ? (amountCollateral - collateralNeeded, 0)
                : (0, collateralNeeded - amountCollateral)
        );
    }
    /*** ERC20 ***/
    function _transfer(address from, address to, uint256 value) internal {
        require(tokensUnlocked(from, value), ErrorHandler.IL());
        super._transfer(from, to, value);
    }
    function tokensUnlocked(address from, uint256 value) public returns (bool) {
        uint256 _balance = this.balanceOf(from);
        if (value > _balance) return false;
        uint256 finalBalance = _balance - value;
        uint256 amountCollateral = (finalBalance * exchangeRate()) / 1e18;
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
        amount0 = amount0 == type(uint256).max
            ? amount0 = IBorrowable(borrowable0).borrowBalance(borrower)
            : amount0;
        amount1 = amount1 == type(uint256).max
            ? amount1 = IBorrowable(borrowable1).borrowBalance(borrower)
            : amount1;
        uint256 amountCollateral = (this.balanceOf(borrower) * exchangeRate()) /
            1e18;
        return _calculateLiquidity(amountCollateral, amount0, amount1);
    }
    function accountLiquidity(
        address borrower
    ) public returns (uint256 liquidity, uint256 shortfall) {
        return
            accountLiquidityAmounts(
                borrower,
                type(uint256).max,
                type(uint256).max
            );
    }
    function canBorrow(
        address borrower,
        address borrowable,
        uint256 accountBorrows
    ) public returns (bool) {
        require(
            borrowable == borrowable0 || borrowable == borrowable1,
            ErrorHandler.IB()
        );
        uint256 amount0 = borrowable == borrowable0
            ? accountBorrows
            : type(uint256).max;
        uint256 amount1 = borrowable == borrowable1
            ? accountBorrows
            : type(uint256).max;
        (, uint256 shortfall) = accountLiquidityAmounts(
            borrower,
            amount0,
            amount1
        );
        return shortfall == 0;
    }
    /// @dev this function must be called from borrowable0 or borrowable1
    function seize(
        address liquidator,
        address borrower,
        uint256 repayAmount
    ) external returns (uint256 seizeTokens) {
        require(
            msg.sender == borrowable0 || msg.sender == borrowable1,
            ErrorHandler.UA()
        );
        (, uint256 shortfall) = accountLiquidity(borrower);
        require(shortfall > 0, ErrorHandler.ISF());
        /// @dev if borrowable0 fetch first slot, else fetch second
        uint256 price = msg.sender == borrowable0
            ? (price, ) = getPrices()
            : (, price) = getPrices();
        seizeTokens =
            (((repayAmount * liquidationIncentive) / 1e18) * price) /
            exchangeRate();
        /// @dev check to ensure not seizing more than balance
        require(seizeTokens <= this.balanceOf(borrower), ErrorHandler.LTM());
        this._transfer(borrower, liquidator, seizeTokens);
        emit Transfer(borrower, liquidator, seizeTokens);
    }
    // this low-level function should be called from another contract
    function flashRedeem(
        address redeemer,
        uint256 redeemAmount,
        bytes calldata data
    ) external nonReentrant update {
        require(redeemAmount <= totalBalance, ErrorHandler.IC());
        // optimistically transfer funds
        _safeTransfer(redeemer, redeemAmount);
        if (data.length > 0)
            ILyfCallee(redeemer).lyfRedeem(msg.sender, redeemAmount, data);
        uint256 redeemTokens = this.balanceOf(address(this));
        uint256 declaredRedeemTokens = ((redeemAmount * 1e18) /
            (exchangeRate())) + 1; // rounded up
        require(redeemTokens >= declaredRedeemTokens, ErrorHandler.IRT());
        _burn(address(this), redeemTokens);
        emit Redeem(msg.sender, redeemer, redeemAmount, redeemTokens);
    }
}
