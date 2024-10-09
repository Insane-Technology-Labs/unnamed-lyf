// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IVault.sol";

/// @dev LyfVaultWrapper is a contract for wrapping auto-compounding vault shares to be used as collateral in the LYF apparatus
contract LyfVaultWrapper is ERC20 {
    address public admin;
    /// @dev LTV = #/100_000
    /// @dev default to 1%
    uint256 public ltv = 1000;
    /// @dev max LTV of 90%
    uint256 public constant MAX_LTV = 90_000;
    uint256 public constant MIN_SHARES = 1e3;
    /// @notice basis (denominator) of 100_000 (100%)
    uint256 public constant BASIS = 100_000;

    /// @dev withdraw fee of 0.1% to prevent shenanigans
    uint256 public constant SECURITY_FEE = 100;

    IVault public underlying;
    address public operator;
    address internal constant DEAD = 0x000000000000000000000000000000000000dEaD;

    /// @notice the amount of ERC4626 (underlying vault) tokens
    /// @dev since they always are 1:1 we don't need special accounting
    uint256 public checkpointedUnderlying;

    /// @dev 0 = false (unpaused)
    /// @dev 1 = true (paused)
    uint8 public paused = 0;

    struct UserPosition {
        address user;
        uint256 index;
        uint256 totalDeposited;
        uint256 initialTimestamp;
        uint256 lastUpdate;
        uint256 closedTime;
        bool closed;
    }

    mapping(address user => mapping(uint256 index => UserPosition))
        public positions;

    modifier whileNotPaused() {
        require(paused == 0, "paused");
        _;
    }

    event newPositionOrUpdate(address user, uint256 index, UserPosition pos);
    constructor(
        address _vaultToken,
        address _operator,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        checkpointedUnderlying = 0;
        underlying = IVault(_vaultToken);
        operator = _operator;
    }

    function mintCollateral(
        uint256 _amount,
        uint256 _positionIndex
    ) external whileNotPaused {
        require(_amount != 0, "zero");
        underlying.transferFrom(msg.sender, address(this), _amount);
        /// @dev if no underlying, mint 1e3 (min shares) and burn them
        if (checkpointedUnderlying == 0) {
            _amount = _burnInitial(_amount);
        }
        checkpointedUnderlying += _amount;
        _mint(msg.sender, _amount);
    }

    /// @notice withdraw your vault tokens from the wrapper
    function withdrawCollateral(uint256 _amount) external {
        require(_amount < checkpointedUnderlying, "insufficient underlying");
        require(_amount != 0, "cannot withdraw 0");
        /// @dev withdraw from the vault
        IVault(underlying).withdraw(_amount);
        /// @dev burn the user's tokens
        _burn(msg.sender, _amount);
    }

    /// @notice pause or unpause this specific vaultWrapper
    function togglePaused() external onlyAdmin {
        paused = paused == 0 ? 1 : 0;
    }

    /// @dev burns the min shares amount to prevent share inflation
    function _burnInitial(uint256 _amount) internal returns (uint256 _amount) {
        require(_amount >= MIN_SHARES, "!Enough");
        checkpointedUnderlying += MIN_SHARES;
        _mint(DEAD, MIN_SHARES);
        _amount -= MIN_SHARES;
    }
}
