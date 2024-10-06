// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "./LyfERC20.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IPoolToken.sol";
import "./ErrorHandler.sol";

contract PoolToken is IPoolToken, LyfERC20 {
    /// @inheritdoc IPoolToken
    address public underlying;
    /// @inheritdoc IPoolToken
    address public factory;
    /// @inheritdoc IPoolToken
    uint256 public totalBalance;
    /// @inheritdoc IPoolToken
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

    /// @inheritdoc IPoolToken
    function _setFactory() external {
        require(factory == address(0), ErrorHandler.FAS());
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
                : ((totalBalance * 1e18) / (totalSupply))
        );
    }

    /// @inheritdoc IPoolToken
    /// @dev this low-level function should be called from another contract
    function mint(
        address minter
    ) external nonReentrant update returns (uint256 mintTokens) {
        uint256 balance = IERC20(underlying).balanceOf(address(this));
        /// @dev difference in underlying balance before updating
        uint256 mintAmount = balance - (totalBalance);
        mintTokens = (mintAmount * 1e18) / exchangeRate();

        if (totalSupply == 0) {
            // permanently lock the first MINIMUM_LIQUIDITY tokens
            mintTokens -= (MINIMUM_LIQUIDITY);
            _mint(address(0), MINIMUM_LIQUIDITY);
        }
        require(mintTokens > 0, ErrorHandler.MAZ());
        _mint(minter, mintTokens);
        emit Mint(msg.sender, minter, mintAmount, mintTokens);
    }

    /// @inheritdoc IPoolToken
    /// @dev this low-level function should be called from another contract
    function redeem(
        address redeemer
    ) external nonReentrant update returns (uint256 redeemAmount) {
        uint256 redeemTokens = this.balanceOf(address(this));
        redeemAmount = (redeemTokens * exchangeRate()) / 1e18;

        require(redeemAmount > 0, ErrorHandler.RAZ());
        require(redeemAmount <= totalBalance, ErrorHandler.IC());
        _burn(address(this), redeemTokens);
        this.transfer(redeemer, redeemAmount);
        emit Redeem(msg.sender, redeemer, redeemAmount, redeemTokens);
    }

    /// @inheritdoc IPoolToken
    function skim(address to) external nonReentrant {
        IERC20(underlying).transfer(
            to,
            IERC20(underlying).balanceOf(address(this)) - totalBalance
        );
    }

    /// @inheritdoc IPoolToken
    function sync() external nonReentrant update {}

    /// @dev prevents a contract from calling itself, directly or indirectly.
    bool internal _notEntered = true;
    modifier nonReentrant() {
        require(_notEntered, "Lyf: REENTERED");
        _notEntered = false;
        _;
        _notEntered = true;
    }

    /// @dev update totalBalance with current balance
    /// @dev called at the END of the function call
    modifier update() {
        _;
        _update();
    }
}
