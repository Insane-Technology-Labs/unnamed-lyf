// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

library ErrorHandler {
    error PriceCalculationError();
    /// @dev insufficient Liq
    error IL();
    /// @dev insufficient cash
    error IC();
    /// @dev already exists
    error AE();
    /// @dev already init
    error AI();
    /// @dev collat not created
    error CNC();
    /// @dev borrow not created
    error BNC();
    /// @dev unauthorized
    error UA();
    /// @dev invalid setting
    error IS();
    /// @dev invalid borrowable
    error IB();
    /// @dev insufficient shortfall
    error ISF();
    /// @dev liquidating too much
    error LTM();
    /// @dev insufficient redeem tokens
    error IRT();
    /// @dev factory already set
    error FAS();
    /// @dev mint amount zero
    error MAZ();
    /// @dev redeem amount zero
    error RAZ();
    /// @dev borrow not allowed
    error BNA();
    /// @dev insufficient A amount
    error IAA();
    /// @dev insufficient B amount
    error IBA();
    /// @dev sender not router
    error SNR();
}
