// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IVault.sol";

/// @dev LyfVaultWrapper is a contract for wrapping auto-compounding vault shares to be used as collateral in the LYF apparatus
contract LyfVaultWrapper is ERC20 {
    address public operator;
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

    /// @notice the underlying vault token receipt
    IVault public underlying;

    address internal constant DEAD = 0x000000000000000000000000000000000000dEaD;
    uint256 public constant CHAIN = block.chainid;

    /// @notice unclaimed fees
    uint256 public take;

    /// @notice global index variable
    uint256 public gIndex;

    /// @notice amount of underlying vault tokens checkpointed
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

    mapping(uint256 index => UserPosition uPos) public positions;

    modifier whileNotPaused() {
        require(paused == 0, "paused");
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == operator, "!Authorized");
        _;
    }

    event NewPositionOrUpdate(
        address indexed user,
        uint256 index,
        UserPosition pos
    );

    event WithdrawPosition(
        address indexed user,
        uint256 amount,
        uint256 index,
        UserPosition pos
    );
    event Sweeped(uint256 _took);
    constructor(
        address _vaultToken,
        address _operator,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        checkpointedUnderlying = 0;
        gIndex = 1;
        underlying = IVault(_vaultToken);
        operator = _operator;
    }

    /// @notice mints collateral 1:1 using the underlying vault token
    /// @param _amount amount of vault tokens to deposit
    /// @param _positionIndex the index of a global position for this specific vault
    function mintCollateral(
        uint256 _amount,
        uint256 _positionIndex
    ) external whileNotPaused {
        require(_amount != 0, "Zero");
        underlying.transferFrom(msg.sender, address(this), _amount);
        /// @dev if no underlying, mint 1e3 (min shares) and burn them
        /// @dev adjusts _amount to prevent over-minting
        if (checkpointedUnderlying == 0) {
            _amount = _burnInitial(_amount);
        }
        /// @dev if index of 0 is chosen, make new position
        if (_positionIndex == 0) {
            /// @dev add to the accounting
            positions[++gIndex] = new UserPosition(
                user = msg.sender,
                index = gIndex,
                totalDeposited = _amount,
                initialTimestamp = block.timestamp,
                lastUpdate = block.timestamp,
                closedTime = 0,
                closed = false
            );
            emit NewPositionOrUpdate(msg.sender, gIndex, positions[gIndex]);
        } else {
            UserPosition memory _uPos = positions[_positionIndex];
            require(!_uPos.closed, "Closed");
            /// @dev increase the deposited amount and updated time
            _uPos.totalDeposited += _amount;
            _uPos.lastUpdate = block.timestamp;
            positions[_positionIndex] = _uPos;
            emit NewPositionOrUpdate(msg.sender, _positionIndex, _uPos);
        }
        checkpointedUnderlying += _amount;
        /// @dev mint tokens to the caller
        _mint(msg.sender, _amount);
    }

    /// @notice withdraw your vault tokens from the wrapper
    /// @param _amount the amount of tokens to withdraw
    function withdrawCollateral(
        uint256 _amount,
        uint256 _positionIndex
    ) external {
        /// @dev amount checks
        require(_amount < available(), "Insufficient Underlying");
        require(_amount != 0, "!W0");

        /// @dev ownership / status checks
        UserPosition memory uPos = positions[_positionIndex];
        require(!uPos.closed && "Closed");
        require(uPos.user == msg.sender, "!Authorized");

        /// @dev balance checks and accounting
        require(uPos.totalDeposited >= _amount, "!Enough");
        require(balanceOf(msg.sender) >= _amount, "!Enough Receipt");

        /// @dev burn the user's tokens
        _burn(msg.sender, _amount);

        /// @dev fee calculation and withdrawal amounts
        uint256 initialAmount = _amount;
        _amount = _updateTake(_amount);
        underlying.transfer(msg.sender, _amount);
        emit WithdrawPosition(msg.sender, initialAmount, _positionIndex, pos);
    }

    /// @notice pause or unpause this specific vaultWrapper
    function togglePaused() external onlyOperator {
        paused = paused == 0 ? 1 : 0;
    }

    /// @dev burns the min shares amount to prevent share inflation
    /// @dev should be called by the contract creator so users dont have to burn
    function _burnInitial(uint256 _amount) internal returns (uint256 _amount) {
        /// @dev ensure the amount passed is greater than the minimum
        require(_amount >= MIN_SHARES, "!Enough");
        /// @dev iterate on the underlying with the burnt shares
        checkpointedUnderlying += MIN_SHARES;
        /// @dev mint the burn shares to the dead address
        _mint(DEAD, MIN_SHARES);
        /// @dev reduce the burnt shares from the amount
        _amount -= MIN_SHARES;
    }

    /// @notice sweeps all pending 'take'
    function sweep() external {
        /// @dev if any pending, claim
        if (take > 0) {
            /// @dev record the take before claiming
            uint256 snapshotTake = take;
            /// @dev reset the take to 0
            take = 0;
            /// @dev transfer the snapshotted amount
            underlying.transfer(operator, snapshotTake);
            emit Sweeped(snapshotTake);
        }
    }

    /// @dev updates the take value and returns the new _amount
    /// @param _amount the amount pre-fee
    function _updateTake(
        uint256 _amount
    ) internal returns (uint256 _newAmount) {
        /// @dev calculate the fee
        uint256 _take = ((_amount * SECURITY_FEE) / BASIS);
        /// @dev update the current global take
        take += _take;
        /// @dev return the new amount subtracting the take
        _newAmount = _amount - _take;
    }

    /// @notice returns the amount of underlying that is readily available
    /// @dev excludes min shares and accrued fees
    /// @return _available the available amount of underlying tokens
    function available() public view returns (uint256 _available) {
        _available = checkpointedUnderlying > (take + MIN_SHARES) /// @dev safe balance
            ? (checkpointedUnderlying - (take + MIN_SHARES)) /// @dev sanity check
            : (0);
    }
}
