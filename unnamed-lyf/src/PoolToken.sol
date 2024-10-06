// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "./LyfERC20.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IPoolToken.sol";
import "./libraries/SafeMath.sol";
import "./ErrorHandler.sol";

contract PoolToken is IPoolToken, LyfERC20 {
    address public underlying;
    address public factory;
    uint256 public totalBalance;
    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    event Mint(
        address indexed sender,
        address indexed minter,
        uint256 mintAmount,
        uint256 mintTokens
    );
    event Redeem(
        address indexed sender,
        address indexed redeemer,
        uint256 redeemAmount,
        uint256 redeemTokens
    );
    event Sync(uint256 totalBalance);

    /*** Initialize ***/

    // called once by the factory
    function _setFactory() external {
        require(factory == address(0), "Lyf: FACTORY_ALREADY_SET");
        factory = msg.sender;
    }

    /*** PoolToken ***/

    function _update() internal {
        totalBalance = IERC20(underlying).balanceOf(address(this));
        emit Sync(totalBalance);
    }

    function exchangeRate() public returns (uint256) {
        return (
            (totalSupply == 0 || totalBalance == 0)
                ? 1e18
                : (totalBalance * (1e18)) / (totalSupply)
        );
    }

    // this low-level function should be called from another contract
    function mint(
        address minter
    ) external nonReentrant update returns (uint256 mintTokens) {
        uint256 balance = IERC20(underlying).balanceOf(address(this));
        uint256 mintAmount = balance - (totalBalance);
        mintTokens = (mintAmount * (1e18)) / (exchangeRate());

        if (totalSupply == 0) {
            // permanently lock the first MINIMUM_LIQUIDITY tokens
            mintTokens -= (MINIMUM_LIQUIDITY);
            _mint(address(0), MINIMUM_LIQUIDITY);
        }
        require(mintTokens > 0, "Lyf: MINT_AMOUNT_ZERO");
        _mint(minter, mintTokens);
        emit Mint(msg.sender, minter, mintAmount, mintTokens);
    }

    // this low-level function should be called from another contract
    function redeem(
        address redeemer
    ) external nonReentrant update returns (uint256 redeemAmount) {
        uint256 redeemTokens = this.balanceOf(address(this));
        redeemAmount = (redeemTokens * (exchangeRate())) / (1e18);

        require(redeemAmount > 0, "Lyf: REDEEM_AMOUNT_ZERO");
        require(redeemAmount <= totalBalance, "Lyf: INSUFFICIENT_CASH");
        _burn(address(this), redeemTokens);
        this.transfer(redeemer, redeemAmount);
        emit Redeem(msg.sender, redeemer, redeemAmount, redeemTokens);
    }

    // force real balance to match totalBalance
    function skim(address to) external nonReentrant {
        _safeTransfer(
            to,
            IERC20(underlying).balanceOf(address(this)) - (totalBalance)
        );
    }

    // force totalBalance to match real balance
    function sync() external nonReentrant update {}

    /*** Utilities ***/

    // same safe transfer function used by UniSwapV2 (with fixed underlying)
    bytes4 private constant SELECTOR =
        bytes4(keccak256(bytes("transfer(address,uint256)")));

    function _safeTransfer(address to, uint256 amount) internal {
        (bool success, bytes memory data) = underlying.call(
            abi.encodeWithSelector(SELECTOR, to, amount)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "Lyf: TRANSFER_FAILED"
        );
    }

    // prevents a contract from calling itself, directly or indirectly.
    bool internal _notEntered = true;
    modifier nonReentrant() {
        require(_notEntered, "Lyf: REENTERED");
        _notEntered = false;
        _;
        _notEntered = true;
    }

    // update totalBalance with current balance
    modifier update() {
        _;
        _update();
    }
}
