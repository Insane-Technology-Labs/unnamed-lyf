// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;
import "./BStorage.sol";
import "./PoolToken.sol";
import "./interfaces/IFactory.sol";

import "./interfaces/IBSetter.sol";
import "./ErrorHandler.sol";

contract BSetter is IBsetter, PoolToken, BStorage {
    uint256 public constant RESERVE_FACTOR_MAX = 0.20e18; //20%
    uint256 public constant KINK_UR_MIN = 0.50e18; //50%
    uint256 public constant KINK_UR_MAX = 0.99e18; //99%
    uint256 public constant ADJUST_SPEED_MIN = 0.05787037e12; //0.5% per day
    uint256 public constant ADJUST_SPEED_MAX = 5.787037e12; //50% per day

    event NewReserveFactor(uint256 newReserveFactor);
    event NewKinkUtilizationRate(uint256 newKinkUtilizationRate);
    event NewAdjustSpeed(uint256 newAdjustSpeed);
    event NewBorrowTracker(address newBorrowTracker);

    modifier authorization() {
        require(msg.sender == factory, ErrorHandler.UA());
    }

    /// @notice function to initialize the BSetter contract
    /// @param _name the string name
    /// @param _symbol the symbol of the token
    /// @param _underlying the address of the underlying token
    /// @param _collateral the collateral token address
    /// @dev called once by the factory at time of deployment
    function _initialize(
        string calldata _name,
        string calldata _symbol,
        address _underlying,
        address _collateral
    ) external authorization {
        _setName(_name, _symbol);
        underlying = _underlying;
        collateral = _collateral;
        exchangeRateLast = initialExchangeRate;
    }
    /// @inheritdoc IBSetter
    function _setReserveFactor(uint256 newReserveFactor) external nonReentrant {
        _checkSetting(newReserveFactor, 0, RESERVE_FACTOR_MAX);
        reserveFactor = newReserveFactor;
        emit NewReserveFactor(newReserveFactor);
    }
    /// @inheritdoc IBSetter
    function _setKinkUtilizationRate(
        uint256 newKinkUtilizationRate
    ) external nonReentrant {
        _checkSetting(newKinkUtilizationRate, KINK_UR_MIN, KINK_UR_MAX);
        kinkUtilizationRate = newKinkUtilizationRate;
        emit NewKinkUtilizationRate(newKinkUtilizationRate);
    }

    /// @inheritdoc IBSetter
    function _setAdjustSpeed(uint256 newAdjustSpeed) external nonReentrant {
        _checkSetting(newAdjustSpeed, ADJUST_SPEED_MIN, ADJUST_SPEED_MAX);
        adjustSpeed = newAdjustSpeed;
        emit NewAdjustSpeed(newAdjustSpeed);
    }
    /// @inheritdoc IBSetter
    function _setBorrowTracker(
        address newBorrowTracker
    ) external nonReentrant authorization {
        borrowTracker = newBorrowTracker;
        emit NewBorrowTracker(newBorrowTracker);
    }

    /// @dev internal function that checks if the parameters are within the pre-set bounds
    function _checkSetting(
        uint256 parameter,
        uint256 min,
        uint256 max
    ) internal authorization {
        require(parameter >= min, ErrorHandler.IS());
        require(parameter <= max, ErrorHandler.IS());
    }
}
