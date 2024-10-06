// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

interface ILyfCallee {
    function tarotBorrow(
        address sender,
        address borrower,
        uint256 borrowAmount,
        bytes calldata data
    ) external;

    function tarotRedeem(
        address sender,
        uint256 redeemAmount,
        bytes calldata data
    ) external;
}
