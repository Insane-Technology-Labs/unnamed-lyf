// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "./CStorage.sol";
import "./PoolToken.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/ILyfPriceOracle.sol";
import "./ErrorHandler.sol";

contract CSetter is PoolToken, CStorage {
    /// @dev safetyMargin: 100%
    uint256 public constant SAFETY_MARGIN_SQRT_MIN = 10e17;
    /// @dev safetyMargin: 250%
    uint256 public constant SAFETY_MARGIN_SQRT_MAX = 1.58113884e18;
    /// @dev 100%
    uint256 public constant LIQUIDATION_INCENTIVE_MIN = 10e17;
    /// @dev 105%
    uint256 public constant LIQUIDATION_INCENTIVE_MAX = 105e16;

    event NewSafetyMargin(uint256 newSafetyMarginSqrt);
    event NewLiquidationIncentive(uint256 newLiquidationIncentive);

    // called once by the factory at the time of deployment
    function _initialize(
        string calldata _name,
        string calldata _symbol,
        address _underlying,
        address _borrowable0,
        address _borrowable1
    ) external {
        require(msg.sender == factory, ErrorHandler.UA());
        _setName(_name, _symbol);
        underlying = _underlying;
        borrowable0 = _borrowable0;
        borrowable1 = _borrowable1;
        lyfPriceOracle = IFactory(factory).lyfPriceOracle();
    }

    function _setSafetyMarginSqrt(
        uint256 newSafetyMarginSqrt
    ) external nonReentrant {
        /// @dev check if within bounds
        _checkSetting(
            newSafetyMarginSqrt,
            SAFETY_MARGIN_SQRT_MIN,
            SAFETY_MARGIN_SQRT_MAX
        );
        /// @dev update new safetyMargin value
        safetyMarginSqrt = newSafetyMarginSqrt;
        emit NewSafetyMargin(newSafetyMarginSqrt);
    }

    function _setLiquidationIncentive(
        uint256 newLiquidationIncentive
    ) external nonReentrant {
        /// @dev check if within bounds
        _checkSetting(
            newLiquidationIncentive,
            LIQUIDATION_INCENTIVE_MIN,
            LIQUIDATION_INCENTIVE_MAX
        );
        /// @dev update new incentive value
        liquidationIncentive = newLiquidationIncentive;
        emit NewLiquidationIncentive(newLiquidationIncentive);
    }

    function _checkSetting(
        uint256 parameter,
        uint256 min,
        uint256 max
    ) internal view {
        require(msg.sender == IFactory(factory).admin(), ErrorHandler.UA());
        require(parameter >= min, ErrorHandler.IS());
        require(parameter <= max, ErrorHandler.IS());
    }
}
