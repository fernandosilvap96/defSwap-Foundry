// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {DefSwapPool} from "../src/DefSwapPool.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DefSwapPoolHandler is Test {
    DefSwapPool pool;
    ERC20Mock defToken;
    ERC20Mock poolToken;

    address liquidityProvider = makeAddr("liquidityProvider");
    address user = makeAddr("user");

    // Our Ghost variables
    int256 public actualDeltaY;
    int256 public expectedDeltaY;

    int256 public actualDeltaX;
    int256 public expectedDeltaX;

    int256 public startingX;
    int256 public startingY;

    constructor(DefSwapPool _pool) {
        pool = _pool;
        defToken = ERC20Mock(address(pool.getDefToken()));
        poolToken = ERC20Mock(address(pool.getPoolToken()));
    }

    function swapPoolTokenForDefTokensBasedOnInputDefTokens(
        uint256 inputDefTokensAmount
    ) public {
        if (
            defToken.balanceOf(address(pool)) <=
            pool.getMinimumDefTokenDepositAmount()
        ) {
            return;
        }
        inputDefTokensAmount = bound(
            inputDefTokensAmount,
            pool.getMinimumDefTokenDepositAmount(),
            defToken.balanceOf(address(pool))
        );
        // If these two values are the same, we will divide by 0
        if (inputDefTokensAmount == defToken.balanceOf(address(pool))) {
            return;
        }
        uint256 poolTokenAmount = pool.getOutputAmountBasedOnInput(
            inputDefTokensAmount, // inputAmount
            defToken.balanceOf(address(pool)), // inputReserves
            poolToken.balanceOf(address(pool)) // outputReserves
        );
        if (poolTokenAmount > type(uint64).max) {
            return;
        }
        // We * -1 since we are removing poolTokens from the system
        _updateStartingDeltas(
            int256(inputDefTokensAmount) * -1,
            int256(poolTokenAmount)
        );

        // Mint any necessary amount of pool tokens
        if (poolToken.balanceOf(user) < poolTokenAmount) {
            poolToken.mint(
                user,
                poolTokenAmount - poolToken.balanceOf(user) + 1
            );
        }

        vm.startPrank(user);
        // Approve tokens so they can be pulled by the pool during the swap
        poolToken.approve(address(pool), type(uint256).max);

        // Execute swap, giving def tokens, receiving poolTokens
        pool.swap({
            inputToken: defToken,
            inputAmount: inputDefTokensAmount,
            outputToken: poolToken,
            deadline: uint64(block.timestamp)
        });
        vm.stopPrank();
        _updateEndingDeltas();
    }

    function deposit(uint256 defTokenAmountToDeposit) public {
        // make the amount to deposit a "reasonable" number. We wouldn't expect someone to have type(uint256).max DEFTOKEN!!
        defTokenAmountToDeposit = bound(
            defTokenAmountToDeposit,
            pool.getMinimumDefTokenDepositAmount(),
            type(uint64).max
        );
        uint256 amountPoolTokensToDepositBasedOnDefToken = pool
            .getPoolTokensToDepositBasedOnDefToken(defTokenAmountToDeposit);
        _updateStartingDeltas(
            int256(defTokenAmountToDeposit),
            int256(amountPoolTokensToDepositBasedOnDefToken)
        );

        vm.startPrank(liquidityProvider);
        defToken.mint(liquidityProvider, defTokenAmountToDeposit);
        poolToken.mint(
            liquidityProvider,
            amountPoolTokensToDepositBasedOnDefToken
        );

        defToken.approve(address(pool), defTokenAmountToDeposit);
        poolToken.approve(
            address(pool),
            amountPoolTokensToDepositBasedOnDefToken
        );

        pool.deposit({
            defTokenToDeposit: defTokenAmountToDeposit,
            minimumLiquidityTokensToMint: 0,
            maximumPoolTokensToDeposit: amountPoolTokensToDepositBasedOnDefToken,
            deadline: uint64(block.timestamp)
        });
        vm.stopPrank();
        _updateEndingDeltas();
    }

    /*//////////////////////////////////////////////////////////////
                    HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _updateStartingDeltas(
        int256 defTokenAmount,
        int256 poolTokenAmount
    ) internal {
        startingY = int256(poolToken.balanceOf(address(pool)));
        startingX = int256(defToken.balanceOf(address(pool)));

        expectedDeltaX = defTokenAmount;
        expectedDeltaY = poolTokenAmount;
    }

    function _updateEndingDeltas() internal {
        uint256 endingPoolTokenBalance = poolToken.balanceOf(address(pool));
        uint256 endingDefTokenBalance = defToken.balanceOf(address(pool));

        // sell tokens == x == poolTokens
        int256 actualDeltaPoolToken = int256(endingPoolTokenBalance) -
            int256(startingY);
        int256 deltaDefToken = int256(endingDefTokenBalance) -
            int256(startingX);

        actualDeltaX = deltaDefToken;
        actualDeltaY = actualDeltaPoolToken;
    }
}
