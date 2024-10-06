// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "./interfaces/IFactory.sol";
import "./interfaces/IBDeployer.sol";
import "./interfaces/IBorrowable.sol";
import "./interfaces/ICDeployer.sol";
import "./interfaces/ICollateral.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/ILyfPriceOracle.sol";
import "./ErrorHandler.sol";

contract Factory is IFactory {
    address public admin;
    address public pendingAdmin;
    address public reservesAdmin;
    address public reservesPendingAdmin;
    address public reservesManager;

    struct LendingPool {
        bool initialized;
        uint24 lendingPoolId;
        address collateral;
        address borrowable0;
        address borrowable1;
    }
    mapping(address => LendingPool) public getLendingPool; // get by UniswapV2Pair
    address[] public allLendingPools; // address of the UniswapV2Pair

    function allLendingPoolsLength() external view returns (uint256) {
        return allLendingPools.length;
    }

    IBDeployer public bDeployer;
    ICDeployer public cDeployer;
    ILyfPriceOracle public lyfPriceOracle;

    event LendingPoolInitialized(
        address indexed uniswapV2Pair,
        address indexed token0,
        address indexed token1,
        address collateral,
        address borrowable0,
        address borrowable1,
        uint256 lendingPoolId
    );
    event NewAdmin(address oldAdmin, address newAdmin);

    constructor(
        address _admin,
        IBDeployer _bDeployer,
        ICDeployer _cDeployer,
        ILyfPriceOracle _lyfPriceOracle
    ) public {
        admin = _admin;
        bDeployer = _bDeployer;
        cDeployer = _cDeployer;
        lyfPriceOracle = _lyfPriceOracle;
        emit NewAdmin(address(0), _admin);
    }

    function _getTokens(
        address uniswapV2Pair
    ) private view returns (address token0, address token1) {
        token0 = IUniswapV2Pair(uniswapV2Pair).token0();
        token1 = IUniswapV2Pair(uniswapV2Pair).token1();
    }

    function _createLendingPool(address uniswapV2Pair) private {
        if (getLendingPool[uniswapV2Pair].lendingPoolId != 0) return;
        allLendingPools.push(uniswapV2Pair);
        getLendingPool[uniswapV2Pair] = LendingPool(
            false,
            uint24(allLendingPools.length),
            address(0),
            address(0),
            address(0)
        );
    }

    function createCollateral(
        address uniswapV2Pair
    ) external returns (address collateral) {
        _getTokens(uniswapV2Pair);
        require(
            getLendingPool[uniswapV2Pair].collateral == address(0),
            ErrorHandler.AE()
        );
        collateral = cDeployer.deployCollateral(uniswapV2Pair);
        ICollateral(collateral)._setFactory();
        _createLendingPool(uniswapV2Pair);
        getLendingPool[uniswapV2Pair].collateral = collateral;
    }

    function createBorrowables(
        address uniswapV2Pair
    ) external returns (address borrowable0, address borrowable1) {
        _getTokens(uniswapV2Pair);
        require(
            getLendingPool[uniswapV2Pair].borrowable0 == address(0),
            ErrorHandler.AE()
        );
        borrowable0 = bDeployer.deployBorrowable(uniswapV2Pair, 0);
        IBorrowable(borrowable0)._setFactory();
        _createLendingPool(uniswapV2Pair);
        getLendingPool[uniswapV2Pair].borrowable0 = borrowable0;

        _getTokens(uniswapV2Pair);
        require(
            getLendingPool[uniswapV2Pair].borrowable1 == address(0),
            ErrorHandler.AE()
        );
        borrowable1 = bDeployer.deployBorrowable(uniswapV2Pair, 1);
        IBorrowable(borrowable1)._setFactory();
        _createLendingPool(uniswapV2Pair);
        getLendingPool[uniswapV2Pair].borrowable1 = borrowable1;
    }

    function initializeLendingPool(address uniswapV2Pair) external {
        (address token0, address token1) = _getTokens(uniswapV2Pair);
        LendingPool memory lPool = getLendingPool[uniswapV2Pair];
        require(!lPool.initialized, ErrorHandler.AI());

        require(lPool.collateral != address(0), ErrorHandler.CNC());
        require(lPool.borrowable0 != address(0), ErrorHandler.BNC());
        require(lPool.borrowable1 != address(0), ErrorHandler.BNC());

        (, , , , , bool oracleInitialized) = lyfPriceOracle.getPair(
            uniswapV2Pair
        );
        if (!oracleInitialized) lyfPriceOracle.initialize(uniswapV2Pair);

        ICollateral(lPool.collateral)._initialize(
            "Lyf Collateral",
            "cTAROT",
            uniswapV2Pair,
            lPool.borrowable0,
            lPool.borrowable1
        );
        IBorrowable(lPool.borrowable0)._initialize(
            "Lyf Borrowable",
            "bTAROT",
            token0,
            lPool.collateral
        );
        IBorrowable(lPool.borrowable1)._initialize(
            "Lyf Borrowable",
            "bTAROT",
            token1,
            lPool.collateral
        );

        getLendingPool[uniswapV2Pair].initialized = true;
        emit LendingPoolInitialized(
            uniswapV2Pair,
            token0,
            token1,
            lPool.collateral,
            lPool.borrowable0,
            lPool.borrowable1,
            lPool.lendingPoolId
        );
    }

    function assignAdmin(address _newAdmin) external {
        require(msg.sender == admin, ErrorHandler.UA());
        address oldAdmin = admin;
        admin = _newAdmin;
        emit NewAdmin(oldAdmin, admin);
    }
}
