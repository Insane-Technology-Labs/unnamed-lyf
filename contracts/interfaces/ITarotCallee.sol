pragma solidity >=0.5.0;

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
