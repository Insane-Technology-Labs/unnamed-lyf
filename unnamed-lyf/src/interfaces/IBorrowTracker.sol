// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

interface IBorrowTracker {
    function trackBorrow(
        address borrower,
        uint borrowBalance,
        uint borrowIndex
    ) external;
}
