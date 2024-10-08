// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

contract BStorage {
    address public collateral;

    mapping(address => mapping(address => uint256)) public borrowAllowance;

    struct BorrowSnapshot {
        uint112 principal; // amount in underlying when the borrow was last updated
        uint112 interestIndex; // borrow index when borrow was last updated
    }
    mapping(address => BorrowSnapshot) internal borrowBalances;

    // use one memory slot
    uint112 public borrowIndex = 1e18;
    uint112 public totalBorrows;
    uint32 public accrualTimestamp = uint32(block.timestamp % 2 ** 32);

    uint256 public exchangeRateLast;

    // use one memory slot
    uint48 public borrowRate;
    uint48 public kinkBorrowRate = 3.1709792e9; //10% per year
    uint32 public rateUpdateTimestamp = uint32(block.timestamp % 2 ** 32);

    uint256 public reserveFactor = 0.10e18; //10%
    uint256 public kinkUtilizationRate = 0.70e18; //70%
    uint256 public adjustSpeed = 0.5787037e12; //5% per day
    address public borrowTracker;

    function safe112(uint256 n) internal pure returns (uint112) {
        require(n < 2 ** 112, "Lyf: SAFE112");
        return uint112(n);
    }
}
