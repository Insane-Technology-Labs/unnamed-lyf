// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "./BStorage.sol";
import "./PoolToken.sol";

contract BAllowance is PoolToken, BStorage {
    event BorrowApproval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    function _borrowApprove(
        address owner,
        address spender,
        uint256 value
    ) internal {
        borrowAllowance[owner][spender] = value;
        emit BorrowApproval(owner, spender, value);
    }

    function borrowApprove(
        address spender,
        uint256 value
    ) external returns (bool tf) {
        _borrowApprove(msg.sender, spender, value);
        return true;
    }

    function _checkBorrowAllowance(
        address owner,
        address spender,
        uint256 value
    ) internal {
        uint256 _borrowAllowance = borrowAllowance[owner][spender];
        if (spender != owner && _borrowAllowance != type(uint256).max) {
            require(_borrowAllowance >= value, ErrorHandler.BNA());
            borrowAllowance[owner][spender] = _borrowAllowance - value;
        }
    }
}
