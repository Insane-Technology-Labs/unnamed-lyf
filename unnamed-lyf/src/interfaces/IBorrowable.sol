// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;
import "./IERC20.sol";

interface IBorrowable is IERC20 {
    event Mint(
        address indexed sender,
        address indexed minter,
        uint256 mintAmount,
        uint256 mintTokens
    );
    event Redeem(
        address indexed sender,
        address indexed redeemer,
        uint256 redeemAmount,
        uint256 redeemTokens
    );
    event Sync(uint256 totalBalance);

    /// @notice address of the underlying borrowable token
    function underlying() external view returns (address);

    /// @notice factory address
    function factory() external view returns (address);

    function totalBalance() external view returns (uint256);

    /// @notice minimum liq that is burned
    function MINIMUM_LIQUIDITY() external pure returns (uint256);

    /// @notice exchange rate of the borrowable
    function exchangeRate() external returns (uint256);

    function mint(address minter) external returns (uint256 mintTokens);

    /// @notice redeem tokens
    /// @param redeemer address that is redeeming
    /// @return redeemAmount the amount of tokens redeemed
    function redeem(address redeemer) external returns (uint256 redeemAmount);

    /// @notice forces real balance to match total
    /// @param to address to send skimmed amounts to
    function skim(address to) external;

    /// @notice forces total to match real balance
    function sync() external;

    function _setFactory() external;

    /*** Borrowable ***/

    event BorrowApproval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
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

    function BORROW_FEE() external pure returns (uint256);

    /// @notice address of the collateral
    function collateral() external view returns (address);

    /// @notice reserve factor (LTVish)
    function reserveFactor() external view returns (uint256);

    function exchangeRateLast() external view returns (uint256);

    function borrowIndex() external view returns (uint256);

    /// @notice total borrows
    function totalBorrows() external view returns (uint256);

    /// @notice user borrow allowances
    function borrowAllowance(
        address owner,
        address spender
    ) external view returns (uint256);

    /// @notice borrow balance of a specific borrower
    /// @param borrower address of the borrower
    /// @return bb borrow balance
    function borrowBalance(address borrower) external view returns (uint256 bb);

    function borrowTracker() external view returns (address);

    /// @notice approve borrowing
    function borrowApprove(
        address spender,
        uint256 value
    ) external returns (bool);

    function borrow(
        address borrower,
        address receiver,
        uint256 borrowAmount,
        bytes calldata data
    ) external;

    /// @notice liquidate a position of a borrower
    /// @param borrower address of borrower
    /// @param liquidator where the incentives should be sent
    /// @return seizeTokens tokens seized
    function liquidate(
        address borrower,
        address liquidator
    ) external returns (uint256 seizeTokens);

    function trackBorrow(address borrower) external;

    /*** Borrowable Interest Rate Model ***/

    event AccrueInterest(
        uint256 interestAccumulated,
        uint256 borrowIndex,
        uint256 totalBorrows
    );
    event CalculateKink(uint256 kinkRate);
    event CalculateBorrowRate(uint256 borrowRate);

    function KINK_BORROW_RATE_MAX() external pure returns (uint256);

    function KINK_BORROW_RATE_MIN() external pure returns (uint256);

    /// @notice multiplier added to kink
    function KINK_MULTIPLIER() external pure returns (uint256);

    function borrowRate() external view returns (uint256);

    /// @notice borrow rate for kink UR
    function kinkBorrowRate() external view returns (uint256);

    /// @notice util rate at which the model exponentiates
    function kinkUtilizationRate() external view returns (uint256);

    /// @notice speed of interest adjustment
    function adjustSpeed() external view returns (uint256);

    /// @notice last time rate updated
    function rateUpdateTimestamp() external view returns (uint32);

    /// @notice timestamp of accrual
    function accrualTimestamp() external view returns (uint32);

    /// @notice force push accrue interest
    function accrueInterest() external;

    /*** Borrowable Setter ***/

    event NewReserveFactor(uint256 newReserveFactor);
    event NewKinkUtilizationRate(uint256 newKinkUtilizationRate);
    event NewAdjustSpeed(uint256 newAdjustSpeed);
    event NewBorrowTracker(address newBorrowTracker);

    function RESERVE_FACTOR_MAX() external pure returns (uint256);

    function KINK_UR_MIN() external pure returns (uint256);

    function KINK_UR_MAX() external pure returns (uint256);

    function ADJUST_SPEED_MIN() external pure returns (uint256);

    function ADJUST_SPEED_MAX() external pure returns (uint256);

    function _initialize(
        string calldata _name,
        string calldata _symbol,
        address _underlying,
        address _collateral
    ) external;

    /// @notice adjust the reserve factor for the lending pool
    function _setReserveFactor(uint256 newReserveFactor) external;

    function _setKinkUtilizationRate(uint256 newKinkUtilizationRate) external;

    /// @notice edits the speed of adjustment
    function _setAdjustSpeed(uint256 newAdjustSpeed) external;

    function _setBorrowTracker(address newBorrowTracker) external;
}
