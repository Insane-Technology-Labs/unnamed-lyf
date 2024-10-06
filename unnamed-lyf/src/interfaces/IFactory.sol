// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

interface IFactory {
    event LendingPoolInitialized(
        address indexed uniswapV2Pair,
        address indexed token0,
        address indexed token1,
        address collateral,
        address borrowable0,
        address borrowable1,
        uint lendingPoolId
    );
    event NewAdmin(address oldAdmin, address newAdmin);

    function admin() external view returns (address admin);
    /// @notice assigns a new admin
    /// @param _newAdmin new admin address
    function assignAdmin(address _newAdmin) external;

    function getLendingPool(
        address uniswapV2Pair
    )
        external
        view
        returns (
            bool initialized,
            uint24 lendingPoolId,
            address collateral,
            address borrowable0,
            address borrowable1
        );
    function allLendingPools(
        uint256
    ) external view returns (address uniswapV2Pair);

    function allLendingPoolsLength() external view returns (uint256 length);

    /// @notice creates the LP collateral for the pair
    /// @param uniswapV2Pair the address of the pool
    /// @return collateral the address of the collateral LP
    function createCollateral(
        address uniswapV2Pair
    ) external returns (address collateral);

    /// @notice creates borrowable0 and borrowable1 for the pair
    /// @param uniswapV2Pair address of the pool
    /// @return borrowable0 address of borrowable0
    /// @return borrowable1 address of borrowable1
    function createBorrowables(
        address uniswapV2Pair
    ) external returns (address borrowable0, address borrowable1);

    /// @notice initializes the lending pool
    /// @param uniswapV2Pair address of the pool
    function initializeLendingPool(address uniswapV2Pair) external;
}
