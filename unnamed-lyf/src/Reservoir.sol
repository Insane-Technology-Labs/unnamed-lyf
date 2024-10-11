// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Reservoir contract which acts as a lending pool for leveraging a vault and/or earning from passively lent tokens
contract Reservoir is ERC20 {
    IERC20 public liquid;

    uint256 public totalSupplied;

    uint256 public accrualIndex;
    /// @notice 10_000 = 100%
    uint256 public constant UTIL_BASE = 10_000;
    uint256 public constant MIN_SHARES = 1e3;
    uint256 public immutable START_INDEX;
    uint256 public immutable MAX_RATE = 2500 * UTIL_BASE;

    uint256 public lastUpdateTimestamp;

    constructor(address _pooledToken) ERC20("TOKEN Reservoir", "resTOKEN") {
        liquid = IERC20(_pooledToken);
        /// @dev usually 1e18
        accrualIndex = 10 ** liquid.decimals();
        START_INDEX = accrualIndex;

        lastUpdateTimestamp = block.timestamp;
    }

    function provide(uint256 _amount, address _to) external {
        uint256 shareAmount = (_amount * startIndex) / accrualIndex;
        _mint(to, shareAmount);
        totalSupplied += _amount;
    }

    function totalAvailable() internal view returns (uint256 available) {
        uint256 curr = liquid.balanceOf(address(this));
        available = curr > MIN_SHARES ? (curr - MIN_SHARES) : 0;
    }

    function utilizationRate() public view returns (uint256 _rate) {
        uint256 _available = totalAvailable();
        uint256 _difference = totalSupplied > _available
            ? totalSupplied - _available
            : 0;

        _rate = _difference > 0 ? ((_difference * UTIL_BASE) / _available) : 0;
    }

    function calculateBorrowAPR(
        uint256 utilizationRate
    ) public view returns (uint256 _apr) {
        /// @dev sanity check
        utilizationRate = utilizationRate > UTIL_BASE
            ? UTIL_BASE
            : utilizationRate;
        /// @dev 8/10th
        uint256 linearStep = (UTIL_BASE * 80) / 100;
        /// @dev max apr for the 1st tier
        /// @dev 1% of total, e.g. at 2500 this is 25% apr
        uint256 _maxLinearT1 = (((UTIL_BASE - linearStep) / 20) * MAX_RATE) /
            UTIL_BASE;

        /// @dev UR <= 80%
        if (utilizationRate <= linearStep) {
            /// @dev utilization % related to linearStep
            uint256 _tieredUtil = ((UTIL_BASE * utilizationRate) / linearStep);
            /// @dev apr is linearly calculated
            _apr = (_maxLinearT1 * _tieredUtil) / UTIL_BASE;
            /// @dev sanity check
            _apr = _apr > _maxLinearT1 ? _maxLinearT1 : _apr;
        } else if (utilizationRate > linearStep) {
            /// @dev the last 20% utilization accrues linearly at an accelerated pace
            /// @dev min apr for this tier
            uint256 _minLinear = _maxLinearT1;
            /// @dev 2/10th
            uint256 denom = UTIL_BASE - linearStep;
            /// @dev utilization % related to linearStep
            uint256 _tieredUtil = (((utilizationRate - linearStep) *
                UTIL_BASE) / denom);
            /// @dev apr is linearly calculated
            _apr =
                _minLinear +
                ((MAX_RATE - _minLinear) * _tieredUtil) /
                UTIL_BASE;
            /// @dev sanity check
            _apr = _apr > MAX_RATE
                ? MAX_RATE
                : _apr < _minLinear
                    ? _minLinear
                    : _apr;
        }
    }
}
