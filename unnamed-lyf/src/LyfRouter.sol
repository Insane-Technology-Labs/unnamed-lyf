// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "./interfaces/IRouter03.sol";
import "./interfaces/IPoolToken.sol";
import "./interfaces/IBorrowable.sol";
import "./interfaces/ICollateral.sol";
import "./interfaces/ILyfCallee.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IVaultToken.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IUniswapV2Pair.sol";

contract LyfRouter is IRouter03, ILyfCallee {

    address public immutable override factory;
    address public immutable override bDeployer;
    address public immutable override cDeployer;
    address public immutable override WETH;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "EXPIRED");
        _;
    }

    modifier checkETH(address poolToken) {
        require(WETH == IPoolToken(poolToken).underlying(), "!WETH");
        _;
    }

    constructor(
        address _factory,
        address _bDeployer,
        address _cDeployer,
        address _WETH
    ) public {
        factory = _factory;
        bDeployer = _bDeployer;
        cDeployer = _cDeployer;
        WETH = _WETH;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    /*** Mint ***/

    function _mint(
        address poolToken,
        address token,
        uint256 amount,
        address from,
        address to
    ) internal virtual returns (uint256 tokens) {
        if (from == address(this))
            TransferHelper.safeTransfer(token, poolToken, amount);
        else TransferHelper.safeTransferFrom(token, from, poolToken, amount);
        tokens = IPoolToken(poolToken).mint(to);
    }

    function mint(
        address poolToken,
        uint256 amount,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256 tokens) {
        return
            _mint(
                poolToken,
                IPoolToken(poolToken).underlying(),
                amount,
                msg.sender,
                to
            );
    }

    function mintETH(
        address poolToken,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        override
        ensure(deadline)
        checkETH(poolToken)
        returns (uint256 tokens)
    {
        IWETH(WETH).deposit{value: msg.value}();
        return _mint(poolToken, WETH, msg.value, address(this), to);
    }

    function mintCollateral(
        address poolToken,
        uint256 amount,
        address to,
        uint256 deadline,
        bytes calldata permitData
    ) external virtual override ensure(deadline) returns (uint256 tokens) {
        address underlying = IPoolToken(poolToken).underlying();
        if (this.isVaultToken(underlying)) {
            address uniswapV2Pair = IVaultToken(underlying).underlying();
            _permit(uniswapV2Pair, amount, deadline, permitData);
            TransferHelper.safeTransferFrom(
                uniswapV2Pair,
                msg.sender,
                underlying,
                amount
            );
            IVaultToken(underlying).mint(poolToken);
            return IPoolToken(poolToken).mint(to);
        } else {
            _permit(underlying, amount, deadline, permitData);
            return _mint(poolToken, underlying, amount, msg.sender, to);
        }
    }

    /*** Redeem ***/

    function redeem(
        address poolToken,
        uint256 tokens,
        address to,
        uint256 deadline,
        bytes memory permitData
    ) public virtual override ensure(deadline) returns (uint256 amount) {
        _permit(poolToken, tokens, deadline, permitData);
        IPoolToken(poolToken).transferFrom(msg.sender, poolToken, tokens);
        address underlying = IPoolToken(poolToken).underlying();
        if (this.isVaultToken(underlying)) {
            IPoolToken(poolToken).redeem(underlying);
            return IVaultToken(underlying).redeem(to);
        } else {
            return IPoolToken(poolToken).redeem(to);
        }
    }

    function redeemETH(
        address poolToken,
        uint256 tokens,
        address to,
        uint256 deadline,
        bytes memory permitData
    )
        public
        virtual
        override
        ensure(deadline)
        checkETH(poolToken)
        returns (uint256 amountETH)
    {
        amountETH = redeem(
            poolToken,
            tokens,
            address(this),
            deadline,
            permitData
        );
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    /*** Borrow ***/

    function borrow(
        address borrowable,
        uint256 amount,
        address to,
        uint256 deadline,
        bytes memory permitData
    ) public virtual override ensure(deadline) {
        _borrowPermit(borrowable, amount, deadline, permitData);
        IBorrowable(borrowable).borrow(msg.sender, to, amount, new bytes(0));
    }

    function borrowETH(
        address borrowable,
        uint256 amountETH,
        address to,
        uint256 deadline,
        bytes memory permitData
    ) public virtual override ensure(deadline) checkETH(borrowable) {
        borrow(borrowable, amountETH, address(this), deadline, permitData);
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    /*** Repay ***/

    function _repayAmount(
        address borrowable,
        uint256 amountMax,
        address borrower
    ) internal virtual returns (uint256 amount) {
        IBorrowable(borrowable).accrueInterest();
        uint256 borrowedAmount = IBorrowable(borrowable).borrowBalance(
            borrower
        );
        amount = amountMax < borrowedAmount ? amountMax : borrowedAmount;
    }

    function repay(
        address borrowable,
        uint256 amountMax,
        address borrower,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256 amount) {
        amount = _repayAmount(borrowable, amountMax, borrower);
        TransferHelper.safeTransferFrom(
            IBorrowable(borrowable).underlying(),
            msg.sender,
            borrowable,
            amount
        );
        IBorrowable(borrowable).borrow(borrower, address(0), 0, new bytes(0));
    }

    function repayETH(
        address borrowable,
        address borrower,
        uint256 deadline
    )
        external
        payable
        virtual
        override
        ensure(deadline)
        checkETH(borrowable)
        returns (uint256 amountETH)
    {
        amountETH = _repayAmount(borrowable, msg.value, borrower);
        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(borrowable, amountETH));
        IBorrowable(borrowable).borrow(borrower, address(0), 0, new bytes(0));
        // refund surpluss eth, if any
        if (msg.value > amountETH)
            TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
    }

    /*** Liquidate ***/

    function liquidate(
        address borrowable,
        uint256 amountMax,
        address borrower,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
        returns (uint256 amount, uint256 seizeTokens)
    {
        amount = _repayAmount(borrowable, amountMax, borrower);
        TransferHelper.safeTransferFrom(
            IBorrowable(borrowable).underlying(),
            msg.sender,
            borrowable,
            amount
        );
        seizeTokens = IBorrowable(borrowable).liquidate(borrower, to);
    }

    function liquidateETH(
        address borrowable,
        address borrower,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        override
        ensure(deadline)
        checkETH(borrowable)
        returns (uint256 amountETH, uint256 seizeTokens)
    {
        amountETH = _repayAmount(borrowable, msg.value, borrower);
        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(borrowable, amountETH));
        seizeTokens = IBorrowable(borrowable).liquidate(borrower, to);
        // refund surpluss eth, if any
        if (msg.value > amountETH)
            TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
    }

    /*** Leverage LP Token ***/

    function _leverage(
        address underlying,
        uint256 amountA,
        uint256 amountB,
        address to
    ) internal virtual {
        address borrowableA = getBorrowable(underlying, 0);
        // mint collateral
        bytes memory borrowBData = abi.encode(
            CalleeData({
                callType: CallType.ADD_LIQUIDITY_AND_MINT,
                underlying: underlying,
                borrowableIndex: 1,
                data: abi.encode(
                    AddLiquidityAndMintCalldata({
                        amountA: amountA,
                        amountB: amountB,
                        to: to
                    })
                )
            })
        );
        // borrow borrowableB
        bytes memory borrowAData = abi.encode(
            CalleeData({
                callType: CallType.BORROWB,
                underlying: underlying,
                borrowableIndex: 0,
                data: abi.encode(
                    BorrowBCalldata({
                        borrower: msg.sender,
                        receiver: address(this),
                        borrowAmount: amountB,
                        data: borrowBData
                    })
                )
            })
        );
        // borrow borrowableA
        IBorrowable(borrowableA).borrow(
            msg.sender,
            address(this),
            amountA,
            borrowAData
        );
    }

    function leverage(
        address underlying,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bytes calldata permitDataA,
        bytes calldata permitDataB
    ) external virtual override ensure(deadline) {
        _borrowPermit(
            getBorrowable(underlying, 0),
            amountADesired,
            deadline,
            permitDataA
        );
        _borrowPermit(
            getBorrowable(underlying, 1),
            amountBDesired,
            deadline,
            permitDataB
        );
        address uniswapV2Pair = getUniswapV2Pair(underlying);
        (uint256 amountA, uint256 amountB) = _optimalLiquidity(
            uniswapV2Pair,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin
        );
        _leverage(underlying, amountA, amountB, to);
    }

    function _addLiquidityAndMint(
        address underlying,
        uint256 amountA,
        uint256 amountB,
        address to
    ) internal virtual {
        (
            address collateral,
            address borrowableA,
            address borrowableB
        ) = getLendingPool(underlying);
        address uniswapV2Pair = getUniswapV2Pair(underlying);
        /// @dev add liquidity to uniswap pair
        IERC20(IBorrowable(borrowableA).underlying()).transfer(
            uniswapV2Pair,
            amountA
        );
        IERC20(IBorrowable(borrowableB).underlying()).transfer(
            uniswapV2Pair,
            amountB
        );
        /// @dev mint LP tokens
        if (this.isVaultToken(underlying))
            IUniswapV2Pair(uniswapV2Pair).mint(underlying);
        IUniswapV2Pair(underlying).mint(collateral);
        /// @dev mint collateral
        ICollateral(collateral).mint(to);
    }

    /*** Deleverage LP Token ***/

    function deleverage(
        address underlying,
        uint256 redeemTokens,
        uint256 amountAMin,
        uint256 amountBMin,
        uint256 deadline,
        bytes calldata permitData
    ) external virtual override ensure(deadline) {
        address collateral = getCollateral(underlying);
        uint256 exchangeRate = ICollateral(collateral).exchangeRate();
        require(redeemTokens > 0, ErrorHandler.RAZ());
        uint256 redeemAmount = ((redeemTokens - 1) * exchangeRate) / 1e18;
        _permit(collateral, redeemTokens, deadline, permitData);
        bytes memory redeemData = abi.encode(
            CalleeData({
                callType: CallType.REMOVE_LIQ_AND_REPAY,
                underlying: underlying,
                borrowableIndex: 0,
                data: abi.encode(
                    RemoveLiqAndRepayCalldata({
                        borrower: msg.sender,
                        redeemTokens: redeemTokens,
                        redeemAmount: redeemAmount,
                        amountAMin: amountAMin,
                        amountBMin: amountBMin
                    })
                )
            })
        );
        /// @dev flashRedeem
        ICollateral(collateral).flashRedeem(
            address(this),
            redeemAmount,
            redeemData
        );
    }

    function _removeLiqAndRepay(
        address underlying,
        address borrower,
        uint256 redeemTokens,
        uint256 redeemAmount,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal virtual {
        (
            address collateral,
            address borrowableA,
            address borrowableB
        ) = getLendingPool(underlying);
        address tokenA = IBorrowable(borrowableA).underlying();
        address tokenB = IBorrowable(borrowableB).underlying();
        address uniswapV2Pair = getUniswapV2Pair(underlying);
        // removeLiquidity
        IUniswapV2Pair(underlying).transfer(underlying, redeemAmount);
        if (this.isVaultToken(underlying))
            IVaultToken(underlying).redeem(uniswapV2Pair);
        /// @dev burn liquidity for underlying tokens from LP
        (uint256 amountAMax, uint256 amountBMax) = IUniswapV2Pair(uniswapV2Pair)
            .burn(address(this));
        require(amountAMax >= amountAMin, ErrorHander.IAA());
        require(amountBMax >= amountBMin, ErrorHander.IBA());
        // repay and refund
        _repayAndRefund(borrowableA, tokenA, borrower, amountAMax);
        _repayAndRefund(borrowableB, tokenB, borrower, amountBMax);
        // repay flash redeem
        ICollateral(collateral).transferFrom(
            borrower,
            collateral,
            redeemTokens
        );
    }

    function _repayAndRefund(
        address borrowable,
        address token,
        address borrower,
        uint256 amountMax
    ) internal virtual {
        //repay
        uint256 amount = _repayAmount(borrowable, amountMax, borrower);
        TransferHelper.safeTransfer(token, borrowable, amount);
        IBorrowable(borrowable).borrow(borrower, address(0), 0, new bytes(0));
        /// @dev refund excess
        if (amountMax > amount) {
            uint256 refundAmount = amountMax - amount;
            if (token == WETH) {
                IWETH(WETH).withdraw(refundAmount);
                TransferHelper.safeTransferETH(borrower, refundAmount);
            } else TransferHelper.safeTransfer(token, borrower, refundAmount);
        }
    }

    /*** Lyf Callee ***/

    enum CallType {
        ADD_LIQUIDITY_AND_MINT,
        BORROWB,
        REMOVE_LIQ_AND_REPAY
    }
    struct CalleeData {
        CallType callType;
        address underlying;
        uint8 borrowableIndex;
        bytes data;
    }
    struct AddLiquidityAndMintCalldata {
        uint256 amountA;
        uint256 amountB;
        address to;
    }
    struct BorrowBCalldata {
        address borrower;
        address receiver;
        uint256 borrowAmount;
        bytes data;
    }
    struct RemoveLiqAndRepayCalldata {
        address borrower;
        uint256 redeemTokens;
        uint256 redeemAmount;
        uint256 amountAMin;
        uint256 amountBMin;
    }

    function tarotBorrow(
        address sender,
        address borrower,
        uint256 borrowAmount,
        bytes calldata data
    ) external virtual override {
        borrower;
        borrowAmount;
        CalleeData memory calleeData = abi.decode(data, (CalleeData));
        address declaredCaller = getBorrowable(
            calleeData.underlying,
            calleeData.borrowableIndex
        );
        // only succeeds if called by a borrowable and if that borrowable has been called by the router
        require(sender == address(this), ErrorHandler.SNR());
        require(msg.sender == declaredCaller, ErrorHandler.UA());
        if (calleeData.callType == CallType.ADD_LIQUIDITY_AND_MINT) {
            AddLiquidityAndMintCalldata memory d = abi.decode(
                calleeData.data,
                (AddLiquidityAndMintCalldata)
            );
            _addLiquidityAndMint(
                calleeData.underlying,
                d.amountA,
                d.amountB,
                d.to
            );
        } else if (calleeData.callType == CallType.BORROWB) {
            BorrowBCalldata memory d = abi.decode(
                calleeData.data,
                (BorrowBCalldata)
            );
            address borrowableB = getBorrowable(calleeData.underlying, 1);
            IBorrowable(borrowableB).borrow(
                d.borrower,
                d.receiver,
                d.borrowAmount,
                d.data
            );
        } else revert();
    }

    function tarotRedeem(
        address sender,
        uint256 redeemAmount,
        bytes calldata data
    ) external virtual override {
        redeemAmount;
        CalleeData memory calleeData = abi.decode(data, (CalleeData));
        address declaredCaller = getCollateral(calleeData.underlying);
        /// @dev only succeeds if called by a collateral and if that collateral has been called by the router
        require(sender == address(this), ErrorHandler.SNR());
        require(msg.sender == declaredCaller, ErrorHandler.UA());
        if (calleeData.callType == CallType.REMOVE_LIQ_AND_REPAY) {
            RemoveLiqAndRepayCalldata memory d = abi.decode(
                calleeData.data,
                (RemoveLiqAndRepayCalldata)
            );
            _removeLiqAndRepay(
                calleeData.underlying,
                d.borrower,
                d.redeemTokens,
                d.redeemAmount,
                d.amountAMin,
                d.amountBMin
            );
        } else revert();
    }

    /*** Utilities ***/

    function _optimalLiquidity(
        address uniswapV2Pair,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) public view virtual returns (uint256 amountA, uint256 amountB) {
        (uint256 reserveA, uint256 reserveB, ) = IUniswapV2Pair(uniswapV2Pair)
            .getReserves();
        uint256 amountBOptimal = _quote(amountADesired, reserveA, reserveB);
        if (amountBOptimal <= amountBDesired) {
            require(amountBOptimal >= amountBMin, ErrorHandler.IBA());
            (amountA, amountB) = (amountADesired, amountBOptimal);
        } else {
            uint256 amountAOptimal = _quote(amountBDesired, reserveB, reserveA);
            assert(amountAOptimal <= amountADesired);
            require(amountAOptimal >= amountAMin, ErrorHandler.IAA());
            (amountA, amountB) = (amountAOptimal, amountBDesired);
        }
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function _quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (uint256 amountB) {
        require(amountA > 0, ErrorHandler.IA());
        require(reserveA > 0 && reserveB > 0, ErrorHandler.IL());
        amountB = (amountA * reserveB) / reserveA;
    }

    function isVaultToken(
        address underlying
    ) external view virtual override returns (bool) {
        if (underlying == WETH) {
            return false;
        }
        try IVaultToken(underlying).isVaultToken() returns (bool result) {
            return result;
        } catch {
            return false;
        }
    }

    function getUniswapV2Pair(
        address underlying
    ) public view virtual override returns (address) {
        try IVaultToken(underlying).underlying() returns (address u) {
            return (u != address(0) ? u : underlying);
        } catch {
            return underlying;
        }
    }

    function getBorrowable(
        address underlying,
        uint8 index
    ) public view virtual override returns (address borrowable) {
        require(index < 2, "TarotRouter: INDEX_TOO_HIGH");
        borrowable = address(
            uint256(
                keccak256(
                    abi.encodePacked(
                        hex"ff",
                        bDeployer,
                        keccak256(abi.encodePacked(factory, underlying, index)),
                        hex"e2178358c9dc0146850e3eed50a8ecc18cf189e86f46d09f1a696530142753e8" // Borrowable bytecode keccak256
                    )
                )
            )
        );
    }

    function getCollateral(
        address underlying
    ) public view virtual override returns (address collateral) {
        collateral = address(
            uint256(
                keccak256(
                    abi.encodePacked(
                        hex"ff",
                        cDeployer,
                        keccak256(abi.encodePacked(factory, underlying)),
                        hex"6389d6f61d6e8491844f94c4542056bfb7bf194236f134f6b6df7b4015430a11" // Collateral bytecode keccak256
                    )
                )
            )
        );
    }

    function getLendingPool(
        address underlying
    )
        public
        view
        virtual
        override
        returns (address collateral, address borrowableA, address borrowableB)
    {
        collateral = getCollateral(underlying);
        borrowableA = getBorrowable(underlying, 0);
        borrowableB = getBorrowable(underlying, 1);
    }
}
