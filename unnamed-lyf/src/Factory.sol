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

    modifier onlyAdmin() {
        require(msg.sender == admin, ErrorHandler.UA());
        _;
    }

    struct LendingPool {
        bool initialized;
        uint24 lendingPoolId;
        address collateral;
        address borrowable0;
        address borrowable1;
    }
    /// @notice get by UniswapV2Pair
    mapping(address => LendingPool) public getLendingPool;
    /// @notice address of the UniswapV2Pair
    address[] public allLendingPools;

    /// @notice returns the length of # of lending pools
    /// @return uint256 length of lending pools
    function allLendingPoolsLength() external view returns (uint256) {
        return allLendingPools.length;
    }

    /// @notice borrowable deployer
    IBDeployer public bDeployer;
    /// @notice collateral deployer
    ICDeployer public cDeployer;
    /// @notice oracle for catching twaps
    ILyfPriceOracle public lyfPriceOracle;

    constructor(
        address _admin,
        IBDeployer _bDeployer,
        ICDeployer _cDeployer,
        ILyfPriceOracle _lyfPriceOracle
    ) {
        admin = _admin;
        bDeployer = _bDeployer;
        cDeployer = _cDeployer;
        lyfPriceOracle = _lyfPriceOracle;
        emit NewAdmin(address(0), _admin);
    }

    function _getTokens(
        address uniswapV2Pair
    ) internal view returns (address token0, address token1) {
        (token0, token1) = (
            IUniswapV2Pair(uniswapV2Pair).token0(),
            IUniswapV2Pair(uniswapV2Pair).token1()
        );
    }

    function _createLendingPool(address uniswapV2Pair) internal {
        /// @dev if the ID is not 0, empty return
        if (getLendingPool[uniswapV2Pair].lendingPoolId != 0) return;
        /// @dev push new pool to the array
        allLendingPools.push(uniswapV2Pair);
        /// @dev update mapping
        getLendingPool[uniswapV2Pair] = LendingPool(
            false,
            uint24(allLendingPools.length),
            address(0),
            address(0),
            address(0)
        );
    }
    /// @inheritdoc IFactory
    function createCollateral(
        address uniswapV2Pair
    ) external returns (address collateral) {
        /// TODO: is this needed?
        _getTokens(uniswapV2Pair);
        /// @dev check that collateral is not uninitialized/address(0)
        require(
            getLendingPool[uniswapV2Pair].collateral == address(0),
            ErrorHandler.AE()
        );
        collateral = cDeployer.deployCollateral(uniswapV2Pair);
        ICollateral(collateral)._setFactory();
        _createLendingPool(uniswapV2Pair);
        getLendingPool[uniswapV2Pair].collateral = collateral;
    }
    /// @inheritdoc IFactory
    function createBorrowables(
        address uniswapV2Pair
    ) external returns (address borrowable0, address borrowable1) {
        /// @dev block each creation in its own section
        {
            /// TODO: is this needed?
            _getTokens(uniswapV2Pair);
            /// @dev ensure borrowable0 is uninitialized
            require(
                getLendingPool[uniswapV2Pair].borrowable0 == address(0),
                ErrorHandler.AE()
            );
            /// @dev deploy borrowable
            borrowable0 = bDeployer.deployBorrowable(uniswapV2Pair, 0);
            /// @dev set factory for borrowable
            IBorrowable(borrowable0)._setFactory();
            /// @dev create the lending pool
            _createLendingPool(uniswapV2Pair);
            /// @dev update mapping to reflect borrowable0
            getLendingPool[uniswapV2Pair].borrowable0 = borrowable0;
        }
        {
            /// TODO: is this needed?
            _getTokens(uniswapV2Pair);
            /// @dev ensure borrowable1 is uninitialized
            require(
                getLendingPool[uniswapV2Pair].borrowable1 == address(0),
                ErrorHandler.AE()
            );
            /// @dev deploy borrowable
            borrowable1 = bDeployer.deployBorrowable(uniswapV2Pair, 1);
            /// @dev set factory for borrowable
            IBorrowable(borrowable1)._setFactory();
            /// @dev create the lending pool
            _createLendingPool(uniswapV2Pair);
            /// @dev update mapping to reflect borrowable1
            getLendingPool[uniswapV2Pair].borrowable1 = borrowable1;
        }
    }
    /// @inheritdoc IFactory
    function initializeLendingPool(address uniswapV2Pair) external {
        (address token0, address token1) = _getTokens(uniswapV2Pair);
        LendingPool memory lPool = getLendingPool[uniswapV2Pair];
        /// @dev ensure pool is not initialized already
        require(!lPool.initialized, ErrorHandler.AI());
        /// @dev collateral creation check
        require(lPool.collateral != address(0), ErrorHandler.CNC());
        /// @dev borrowable creation check
        require(
            lPool.borrowable0 != address(0) && lPool.borrowable1 != address(0),
            ErrorHandler.BNC()
        );

        (, , , , , bool oracleInitialized) = lyfPriceOracle.getPair(
            uniswapV2Pair
        );
        /// @dev if the oracle isn't init
        if (!oracleInitialized) lyfPriceOracle.initialize(uniswapV2Pair);
        /// @dev block of all initializes
        {
            ICollateral(lPool.collateral)._initialize(
                "Lyf Collateral",
                "cLYF",
                uniswapV2Pair,
                lPool.borrowable0,
                lPool.borrowable1
            );
            IBorrowable(lPool.borrowable0)._initialize(
                "Lyf Borrowable",
                "bLYF",
                token0,
                lPool.collateral
            );
            IBorrowable(lPool.borrowable1)._initialize(
                "Lyf Borrowable",
                "bLYF",
                token1,
                lPool.collateral
            );
        }

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
    /// @inheritdoc IFactory
    function assignAdmin(address _newAdmin) external onlyAdmin {
        address oldAdmin = admin;
        admin = _newAdmin;
        emit NewAdmin(oldAdmin, admin);
    }
}
