// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "./CStorage.sol";
import "./PoolToken.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/ILyfPriceOracle.sol";
import "./ErrorHandler.sol";

contract CSetter is PoolToken, CStorage {
    uint256 public constant SAFETY_MARGIN_SQRT_MIN = 1.00e18; //safetyMargin: 100%
    uint256 public constant SAFETY_MARGIN_SQRT_MAX = 1.58113884e18; //safetyMargin: 250%
    uint256 public constant LIQUIDATION_INCENTIVE_MIN = 1.00e18; //100%
    uint256 public constant LIQUIDATION_INCENTIVE_MAX = 1.05e18; //105%

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
        require(msg.sender == factory, "Lyf: UNAUTHORIZED"); // sufficient check
        _setName(_name, _symbol);
        underlying = _underlying;
        borrowable0 = _borrowable0;
        borrowable1 = _borrowable1;
        tarotPriceOracle = IFactory(factory).tarotPriceOracle();
    }

    function _setSafetyMarginSqrt(
        uint256 newSafetyMarginSqrt
    ) external nonReentrant {
        _checkSetting(
            newSafetyMarginSqrt,
            SAFETY_MARGIN_SQRT_MIN,
            SAFETY_MARGIN_SQRT_MAX
        );
        safetyMarginSqrt = newSafetyMarginSqrt;
        emit NewSafetyMargin(newSafetyMarginSqrt);
    }

    function _setLiquidationIncentive(
        uint256 newLiquidationIncentive
    ) external nonReentrant {
        _checkSetting(
            newLiquidationIncentive,
            LIQUIDATION_INCENTIVE_MIN,
            LIQUIDATION_INCENTIVE_MAX
        );
        liquidationIncentive = newLiquidationIncentive;
        emit NewLiquidationIncentive(newLiquidationIncentive);
    }

    function _checkSetting(
        uint256 parameter,
        uint256 min,
        uint256 max
    ) internal view {
        _checkAdmin();
        require(parameter >= min, "Lyf: INVALID_SETTING");
        require(parameter <= max, "Lyf: INVALID_SETTING");
    }

    function _checkAdmin() internal view {
        require(msg.sender == IFactory(factory).admin(), ErrorHandler.UA());
    }
}
