// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

interface IBSetter {
    /// @notice MAX reserve factor, upper limit
    function RESERVE_FACTOR_MAX() external view returns (uint256);
    /// @notice MIN Kink util rate, lower limit
    function KINK_UR_MIN() external view returns (uint256);
    /// @notice MAX Kink util rate, upper limit
    function KINK_UR_MAX() external view returns (uint256);
    /// @notice MIN adjusting speed, lower limit
    function ADJUST_SPEED_MIN() external view returns (uint256);
    /// @notice MAX adjusting speed, upper limit
    function ADJUST_SPEED_MAX() external view returns (uint256);
}
