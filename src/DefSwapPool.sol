// SPDX-License-Identifier: GNU General Public License v3.0
pragma solidity 0.8.20;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DefSwapPool is ERC20 {
    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/
    error DefSwapPool__DeadlineHasPassed(uint64 deadline);
    error DefSwapPool__MaxPoolTokenDepositTooHigh(
        uint256 maximumPoolTokensToDeposit,
        uint256 poolTokensToDeposit
    );
    error DefSwapPool__MinLiquidityTokensToMintTooLow(
        uint256 minimumLiquidityTokensToMint,
        uint256 liquidityTokensToMint
    );
    error DefSwapPool__DefTokenDepositAmountTooLow(
        uint256 minimumDefTokenDeposit,
        uint256 defTokenToDeposit
    );
    error DefSwapPool__InvalidToken();
    error DefSwapPool__OutputTooLow(uint256 actual, uint256 min);
    error DefSwapPool__MustBeMoreThanZero();

    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    IERC20 private immutable i_defToken;
    IERC20 private immutable i_poolToken;
    uint256 private constant TOTAL_AMOUNT = 1000; // represent 100% of the amount -> to be used in amount math
    uint256 private constant LP_FEE = 3; // represents fee of 0.03% -> to be used in amount math
    uint256 private constant MINIMUM_DEFTOKEN_AMOUNT = 1_000_000_000; // the minimum amount of defToken that must be deposit

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event LiquidityAdded(
        address indexed liquidityProvider,
        uint256 defTokenDeposited,
        uint256 poolTokensDeposited
    );
    event LiquidityRemoved(
        address indexed liquidityProvider,
        uint256 defTokenWithdrawn,
        uint256 poolTokensWithdrawn
    );
    event Swap(
        address indexed swapper,
        IERC20 tokenIn,
        uint256 amountTokenIn,
        IERC20 tokenOut,
        uint256 amountTokenOut
    );

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier revertIfDeadlinePassed(uint64 deadline) {
        if (deadline < uint64(block.timestamp)) {
            revert DefSwapPool__DeadlineHasPassed(deadline);
        }
        _;
    }

    modifier revertIfZero(uint256 amount) {
        if (amount == 0) {
            revert DefSwapPool__MustBeMoreThanZero();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(
        address poolToken,
        address defToken,
        string memory liquidityTokenName,
        string memory liquidityTokenSymbol
    ) ERC20(liquidityTokenName, liquidityTokenSymbol) {
        i_defToken = IERC20(defToken);
        i_poolToken = IERC20(poolToken);
    }

    /*//////////////////////////////////////////////////////////////
                        ADD AND REMOVE LIQUIDITY
    //////////////////////////////////////////////////////////////*/

    /// @notice Adds liquidity to the pool
    /// @dev The invariant of this function is that the ratio of DEFTOKEN, PoolTokens, and LiquidityTokens is the same before and after the transaction
    /// @param defTokenToDeposit Amount of DEFTOKEN the user is going to deposit
    /// @param minimumLiquidityTokensToMint We derive the amount of liquidity tokens to mint from the amount of DEFTOKEN the user is going to deposit, but set a minimum so they know approx what they will accept
    /// @param maximumPoolTokensToDeposit The maximum amount of pool tokens the user is willing to deposit, again it's derived from the amount of DEFTOKEN the user is going to deposit
    /// @param deadline The deadline for the transaction to be completed
    function deposit(
        uint256 defTokenToDeposit,
        uint256 minimumLiquidityTokensToMint,
        uint256 maximumPoolTokensToDeposit,
        uint64 deadline
    )
        external
        revertIfZero(defTokenToDeposit)
        revertIfDeadlinePassed(deadline)
        returns (uint256 liquidityTokensToMint)
    {
        if (defTokenToDeposit < MINIMUM_DEFTOKEN_AMOUNT) {
            revert DefSwapPool__DefTokenDepositAmountTooLow(
                MINIMUM_DEFTOKEN_AMOUNT,
                defTokenToDeposit
            );
        }
        // in case of this pool already has liquidityTokens (The first deposit had already been called)
        if (totalLiquidityTokenSupply() > 0) {
            // defToken, poolTokens, and liquidity tokens must always have the same ratio after the initial deposit
            uint256 defTokenReserves = i_defToken.balanceOf(address(this));
            uint256 poolTokensToDeposit = getPoolTokensToDepositBasedOnDefToken(
                defTokenToDeposit
            );
            if (maximumPoolTokensToDeposit < poolTokensToDeposit) {
                revert DefSwapPool__MaxPoolTokenDepositTooHigh(
                    maximumPoolTokensToDeposit,
                    poolTokensToDeposit
                );
            }
            liquidityTokensToMint =
                (defTokenToDeposit * totalLiquidityTokenSupply()) /
                defTokenReserves;
            if (liquidityTokensToMint < minimumLiquidityTokensToMint) {
                revert DefSwapPool__MinLiquidityTokensToMintTooLow(
                    minimumLiquidityTokensToMint,
                    liquidityTokensToMint
                );
            }
            _addLiquidityMintAndTransfer(
                defTokenToDeposit,
                poolTokensToDeposit,
                liquidityTokensToMint
            );
        } else {
            // This will be the "initial" funding of the protocol.
            // We just have them send the tokens in, and we mint liquidity tokens based on the defToken
            liquidityTokensToMint = defTokenToDeposit;
            _addLiquidityMintAndTransfer(
                defTokenToDeposit,
                maximumPoolTokensToDeposit,
                defTokenToDeposit
            );
        }
    }

    /// @dev This is a sensitive function, and should only be called by addLiquidity
    /// @param defTokenToDeposit The amount of DEFTOKEN the user is going to deposit
    /// @param poolTokensToDeposit The amount of pool tokens the user is going to deposit
    /// @param liquidityTokensToMint The amount of liquidity tokens the user is going to mint
    function _addLiquidityMintAndTransfer(
        uint256 defTokenToDeposit,
        uint256 poolTokensToDeposit,
        uint256 liquidityTokensToMint
    ) private {
        _mint(msg.sender, liquidityTokensToMint);
        emit LiquidityAdded(msg.sender, defTokenToDeposit, poolTokensToDeposit);

        // External Interactions (The DefSwapPool need to be approved to transfer for the user in each token contract)
        i_defToken.safeTransferFrom(
            msg.sender,
            address(this),
            defTokenToDeposit
        );
        i_poolToken.safeTransferFrom(
            msg.sender,
            address(this),
            poolTokensToDeposit
        );
    }

    /// @notice Removes liquidity from the pool
    /// @param liquidityTokensToBurn The number of liquidity tokens the user wants to burn
    /// @param minDefTokenToWithdraw The minimum amount of DEFTOKEN the user wants to withdraw
    /// @param minPoolTokensToWithdraw The minimum amount of pool tokens the user wants to withdraw
    /// @param deadline The deadline for the transaction to be completed by
    function withdraw(
        uint256 liquidityTokensToBurn,
        uint256 minDefTokenToWithdraw,
        uint256 minPoolTokensToWithdraw,
        uint64 deadline
    )
        external
        revertIfDeadlinePassed(deadline)
        revertIfZero(liquidityTokensToBurn)
        revertIfZero(minDefTokenToWithdraw)
        revertIfZero(minPoolTokensToWithdraw)
    {
        // We do the same math as in deposit
        uint256 defTokenToWithdraw = (liquidityTokensToBurn *
            i_defToken.balanceOf(address(this))) / totalLiquidityTokenSupply();
        uint256 poolTokensToWithdraw = (liquidityTokensToBurn *
            i_poolToken.balanceOf(address(this))) / totalLiquidityTokenSupply();

        if (defTokenToWithdraw < minDefTokenToWithdraw) {
            revert DefSwapPool__OutputTooLow(
                defTokenToWithdraw,
                minDefTokenToWithdraw
            );
        }
        if (poolTokensToWithdraw < minPoolTokensToWithdraw) {
            revert DefSwapPool__OutputTooLow(
                poolTokensToWithdraw,
                minPoolTokensToWithdraw
            );
        }

        _burn(msg.sender, liquidityTokensToBurn);
        emit LiquidityRemoved(
            msg.sender,
            defTokenToWithdraw,
            poolTokensToWithdraw
        );

        // External Interactions
        i_defToken.safeTransfer(msg.sender, defTokenToWithdraw);
        i_poolToken.safeTransfer(msg.sender, poolTokensToWithdraw);
    }

    /*//////////////////////////////////////////////////////////////
                    GET PRICING BASED ON THE LP FEE
    //////////////////////////////////////////////////////////////*/

    /// @notice Make the calculation of amounts considering the fee for the LP holders
    /// @param inputAmount The input amount of the chosen token
    /// @param inputReserves The pool balance of the chosen token
    /// @param outputReserves The pool balance of the paired token
    function getOutputAmountBasedOnInput(
        uint256 inputAmount,
        uint256 inputReserves,
        uint256 outputReserves
    )
        public
        pure
        revertIfZero(inputAmount)
        revertIfZero(outputReserves)
        returns (uint256 outputAmount)
    {
        uint256 inputAmountMinusFee = inputAmount * (TOTAL_AMOUNT - LP_FEE);
        uint256 numerator = inputAmountMinusFee * outputReserves;
        uint256 denominator = (inputReserves * TOTAL_AMOUNT) +
            inputAmountMinusFee;
        return numerator / denominator;
    }

    /// @notice Make the tokens swap
    /// @param inputToken The input token (i_defToken or i_poolToken)
    /// @param inputAmount The amount of the chosen token
    /// @param outputToken The paired token
    /// @param deadline The deadline for the transaction to be completed
    function swap(
        IERC20 inputToken,
        uint256 inputAmount,
        IERC20 outputToken,
        uint64 deadline
    )
        public
        revertIfZero(inputAmount)
        revertIfDeadlinePassed(deadline)
        returns (uint256 outputAmount)
    {
        uint256 inputReserves = inputToken.balanceOf(address(this));
        uint256 outputReserves = outputToken.balanceOf(address(this));

        outputAmount = getOutputAmountBasedOnInput(
            inputAmount,
            inputReserves,
            outputReserves
        );

        _swap(inputToken, inputAmount, outputToken, outputAmount);
    }

    /**
     * @notice wrapper function to facilitate users selling pool tokens in exchange of DEFTOKEN
     * @param poolTokenAmount amount of pool tokens to sell
     * @return defTokenAmount amount of DEFTOKEN received by caller
     */
    function sellPoolTokens(
        uint256 poolTokenAmount
    ) external returns (uint256 defTokenAmount) {
        return
            swap(
                i_poolToken,
                poolTokenAmount,
                i_defToken,
                uint64(block.timestamp)
            );
    }

    /**
     * @notice Swaps a given amount of input for a given amount of output tokens.
     * @dev Checks core invariant of the contract. Beware of modifying this function.
     * @param inputToken ERC20 token to pull from caller
     * @param inputAmount Amount of tokens to pull from caller
     * @param outputToken ERC20 token to send to caller
     * @param outputAmount Amount of tokens to send to caller
     */
    function _swap(
        IERC20 inputToken,
        uint256 inputAmount,
        IERC20 outputToken,
        uint256 outputAmount
    ) private {
        if (
            _isUnknown(inputToken) ||
            _isUnknown(outputToken) ||
            inputToken == outputToken
        ) {
            revert DefSwapPool__InvalidToken();
        }

        emit Swap(
            msg.sender,
            inputToken,
            inputAmount,
            outputToken,
            outputAmount
        );

        // External Interactions
        inputToken.safeTransferFrom(msg.sender, address(this), inputAmount);
        outputToken.safeTransfer(msg.sender, outputAmount);
    }

    function _isUnknown(IERC20 token) private view returns (bool) {
        if (token != i_defToken && token != i_poolToken) {
            return true;
        }
        return false;
    }

    /*//////////////////////////////////////////////////////////////
                   EXTERNAL AND PUBLIC VIEW AND PURE
    //////////////////////////////////////////////////////////////*/
    function getPoolTokensToDepositBasedOnDefToken(
        uint256 defTokenToDeposit
    ) public view returns (uint256) {
        uint256 poolTokenReserves = i_poolToken.balanceOf(address(this));
        uint256 defTokenReserves = i_defToken.balanceOf(address(this));
        return (defTokenToDeposit * poolTokenReserves) / defTokenReserves;
    }

    /// @notice a more verbose way of getting the total supply of liquidity tokens
    function totalLiquidityTokenSupply() public view returns (uint256) {
        return totalSupply();
    }

    function getPoolToken() external view returns (address) {
        return address(i_poolToken);
    }

    function getDefToken() external view returns (address) {
        return address(i_defToken);
    }

    function getMinimumDefTokenDepositAmount() external pure returns (uint256) {
        return MINIMUM_DEFTOKEN_AMOUNT;
    }

    function getPriceOfOneDefTokenInPoolTokens()
        external
        view
        returns (uint256)
    {
        return
            getOutputAmountBasedOnInput(
                1e18,
                i_defToken.balanceOf(address(this)),
                i_poolToken.balanceOf(address(this))
            );
    }

    function getPriceOfOnePoolTokenInDefToken()
        external
        view
        returns (uint256)
    {
        return
            getOutputAmountBasedOnInput(
                1e18,
                i_poolToken.balanceOf(address(this)),
                i_defToken.balanceOf(address(this))
            );
    }
}
