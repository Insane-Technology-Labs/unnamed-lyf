// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "./PoolToken.sol";
import "./BAllowance.sol";
import "./BInterestRateModel.sol";
import "./BSetter.sol";
import "./BStorage.sol";
import "./interfaces/IBorrowable.sol";
import "./interfaces/ICollateral.sol";
import "./interfaces/ILyfCallee.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IBorrowTracker.sol";
import "./libraries/Math.sol";

contract Borrowable is
    IBorrowable,
    PoolToken,
    BStorage,
    BSetter,
    BInterestRateModel,
    BAllowance
{
    uint256 public constant BORROW_FEE = 1e15; //0.1%

    event Borrow(
        address indexed sender,
        address indexed borrower,
        address indexed receiver,
        uint256 borrowAmount,
        uint256 repayAmount,
        uint256 accountBorrowsPrior,
        uint256 accountBorrows,
        uint256 totalBorrows
    );
    event Liquidate(
        address indexed sender,
        address indexed borrower,
        address indexed liquidator,
        uint256 seizeTokens,
        uint256 repayAmount,
        uint256 accountBorrowsPrior,
        uint256 accountBorrows,
        uint256 totalBorrows
    );

    constructor() public {}

    /*** PoolToken ***/

    function _update() internal {
        super._update();
        _calculateBorrowRate();
    }

    function _mintReserves(
        uint256 _exchangeRate,
        uint256 _totalSupply
    ) internal returns (uint256) {
        /// @dev if _exchangeRate is larger than the last exchangeRate calculated
        if (_exchangeRate > exchangeRateLast) {
            uint256 _exchangeRateNew = (_exchangeRate -
                (_exchangeRate - (exchangeRateLast * reserveFactor)) /
                1e18);
            uint256 liquidity = (((_totalSupply * _exchangeRate) /
                (_exchangeRateNew)) - _totalSupply);
            /// @dev if 0  liq, return exchangeRate
            if (liquidity == 0) return _exchangeRate;
            /// @dev mint the reserves to the manager
            address reservesManager = IFactory(factory).reservesManager();
            _mint(reservesManager, liquidity);
            /// @dev set last exchange rate to the newest
            exchangeRateLast = _exchangeRateNew;
            return _exchangeRateNew;
        }
        /// @dev else return the passed _exchangeRate
        else return _exchangeRate;
    }

    function exchangeRate() public accrue returns (uint256) {
        uint256 _totalSupply = this.totalSupply();
        uint256 _actualBalance = totalBalance + totalBorrows;
        if (_totalSupply == 0 || _actualBalance == 0) return 1e18;
        uint256 _exchangeRate = (_actualBalance * 1e18) / _totalSupply;
        return _mintReserves(_exchangeRate, _totalSupply);
    }

    /// @notice force the totalBalance to match real balance
    function sync() external nonReentrant update accrue {}

    /*** Borrowable ***/

    // this is the stored borrow balance; the current borrow balance may be slightly higher
    function borrowBalance(address borrower) public view returns (uint256) {
        BorrowSnapshot memory borrowSnapshot = borrowBalances[borrower];
        /// @dev return 0 if not initialized
        return (
            borrowSnapshot.interestIndex == 0
                ? 0
                : ((uint256(borrowSnapshot.principal) * borrowIndex) /
                    (borrowSnapshot.interestIndex))
        );
    }

    function _trackBorrow(
        address borrower,
        uint256 accountBorrows,
        uint256 _borrowIndex
    ) internal {
        address _borrowTracker = borrowTracker;
        if (_borrowTracker == address(0)) return;
        IBorrowTracker(_borrowTracker).trackBorrow(
            borrower,
            accountBorrows,
            _borrowIndex
        );
    }

    function _updateBorrow(
        address borrower,
        uint256 borrowAmount,
        uint256 repayAmount
    )
        private
        returns (
            uint256 accountBorrowsPrior,
            uint256 accountBorrows,
            uint256 _totalBorrows
        )
    {
        accountBorrowsPrior = borrowBalance(borrower);
        if (borrowAmount == repayAmount)
            return (accountBorrowsPrior, accountBorrowsPrior, totalBorrows);
        uint112 _borrowIndex = borrowIndex;
        if (borrowAmount > repayAmount) {
            BorrowSnapshot storage borrowSnapshot = borrowBalances[borrower];
            uint256 increaseAmount = borrowAmount - repayAmount;
            accountBorrows = accountBorrowsPrior + increaseAmount;
            borrowSnapshot.principal = safe112(accountBorrows);
            borrowSnapshot.interestIndex = _borrowIndex;
            _totalBorrows = uint256(totalBorrows) + increaseAmount;
            totalBorrows = safe112(_totalBorrows);
        } else {
            BorrowSnapshot storage borrowSnapshot = borrowBalances[borrower];
            uint256 decreaseAmount = repayAmount - borrowAmount;
            accountBorrows = accountBorrowsPrior > decreaseAmount
                ? accountBorrowsPrior - decreaseAmount
                : 0;
            borrowSnapshot.principal = safe112(accountBorrows);
            if (accountBorrows == 0) {
                borrowSnapshot.interestIndex = 0;
            } else {
                borrowSnapshot.interestIndex = _borrowIndex;
            }
            uint256 actualDecreaseAmount = accountBorrowsPrior.sub(
                accountBorrows
            );
            _totalBorrows = totalBorrows; // gas savings
            _totalBorrows = _totalBorrows > actualDecreaseAmount
                ? _totalBorrows - actualDecreaseAmount
                : 0;
            totalBorrows = safe112(_totalBorrows);
        }
        _trackBorrow(borrower, accountBorrows, _borrowIndex);
    }

    // this low-level function should be called from another contract
    function borrow(
        address borrower,
        address receiver,
        uint256 borrowAmount,
        bytes calldata data
    ) external nonReentrant update accrue {
        uint256 _totalBalance = totalBalance;
        require(borrowAmount <= _totalBalance, ErrorHandler.IC());
        _checkBorrowAllowance(borrower, msg.sender, borrowAmount);

        // optimistically transfer funds
        if (borrowAmount > 0) _safeTransfer(receiver, borrowAmount);
        if (data.length > 0)
            ILyfCallee(receiver).tarotBorrow(
                msg.sender,
                borrower,
                borrowAmount,
                data
            );
        /// @dev underlying balance of this contract
        uint256 balance = IERC20(underlying).balanceOf(address(this));

        uint256 borrowFee = (borrowAmount * BORROW_FEE) / 1e18;
        uint256 adjustedBorrowAmount = borrowAmount + borrowFee;
        uint256 repayAmount = balance + borrowAmount - _totalBalance;
        (
            uint256 accountBorrowsPrior,
            uint256 accountBorrows,
            uint256 _totalBorrows
        ) = _updateBorrow(borrower, adjustedBorrowAmount, repayAmount);

        if (adjustedBorrowAmount > repayAmount)
            require(
                ICollateral(collateral).canBorrow(
                    borrower,
                    address(this),
                    accountBorrows
                ),
                ErrorHandler.IL()
            );

        emit Borrow(
            msg.sender,
            borrower,
            receiver,
            borrowAmount,
            repayAmount,
            accountBorrowsPrior,
            accountBorrows,
            _totalBorrows
        );
    }

    // this low-level function should be called from another contract
    function liquidate(
        address borrower,
        address liquidator
    ) external nonReentrant update accrue returns (uint256 seizeTokens) {
        /// @dev underlying balance of this contract
        uint256 underlyingBalance = IERC20(underlying).balanceOf(address(this));
        /// @dev suggested repayment amount
        uint256 repayAmount = underlyingBalance - totalBalance;

        /// @dev calculate actual repayment amount by checking minimum
        uint256 actualRepayAmount = borrowBalance(borrower) < repayAmount
            ? borrowBalance(borrower)
            : repayAmount;
        /// @dev seize the tokens to liquidator
        seizeTokens = ICollateral(collateral).seize(
            liquidator,
            borrower,
            actualRepayAmount
        );
        /// @dev update borrow data
        (
            uint256 accountBorrowsPrior,
            uint256 accountBorrows,
            uint256 _totalBorrows
        ) = _updateBorrow(borrower, 0, repayAmount);

        /// @dev emit event for liquidation
        emit Liquidate(
            msg.sender,
            borrower,
            liquidator,
            seizeTokens,
            repayAmount,
            accountBorrowsPrior,
            accountBorrows,
            _totalBorrows
        );
    }

    function trackBorrow(address borrower) external {
        _trackBorrow(borrower, borrowBalance(borrower), borrowIndex);
    }

    modifier accrue() {
        accrueInterest();
        _;
    }
}
