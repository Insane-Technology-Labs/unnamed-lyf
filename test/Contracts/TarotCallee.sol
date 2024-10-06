pragma solidity ^0.8.20;

import "../..//interfaces/ILyfCallee.sol";
import "./Recipient.sol";

contract LyfCallee is ILyfCallee {
    address recipient;
    address underlying;

    constructor(address _recipient, address _underlying) public {
        recipient = _recipient;
        underlying = _underlying;
    }

    function lyfBorrow(
        address sender,
        address borrower,
        uint256 borrowAmount,
        bytes calldata data
    ) external {
        sender;
        borrower;
        borrowAmount;
        data;
        Recipient(recipient).empty(underlying, msg.sender);
    }

    function lyfRedeem(
        address sender,
        uint256 redeemAmount,
        bytes calldata data
    ) external {
        sender;
        redeemAmount;
        data;
        Recipient(recipient).empty(underlying, msg.sender);
    }
}
