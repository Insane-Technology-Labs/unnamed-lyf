// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.5.16;

import "./BStorage.sol";
import "./PoolToken.sol";

/// @dev borrow not allowed
error BNA();

contract BAllowance is PoolToken, BStorage {	

	event BorrowApproval(address indexed owner, address indexed spender, uint256 value);

	function _borrowApprove(address owner, address spender, uint256 value) private {
		borrowAllowance[owner][spender] = value;
		emit BorrowApproval(owner, spender, value);
	}
	
	function borrowApprove(address spender, uint256 value) external returns (bool) {
		_borrowApprove(msg.sender, spender, value);
		return true;
	}
	
	function _checkBorrowAllowance(address owner, address spender, uint256 value) internal {
		uint _borrowAllowance = borrowAllowance[owner][spender];
		if (spender != owner && _borrowAllowance != uint256(-1)) {
			require(_borrowAllowance >= value, BNA());
			borrowAllowance[owner][spender] = _borrowAllowance - value;
		}	
	}

}