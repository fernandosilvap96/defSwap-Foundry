// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, StdInvariant, console2} from "forge-std/Test.sol";
import {PoolFactory} from "../src/PoolFactory.sol";
import {DefSwapPool} from "../src/DefSwapPool.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {DefSwapPoolHandler} from "./DefSwapPoolHandler.t.sol";

contract Invariant is StdInvariant, Test {
    PoolFactory factory;
    DefSwapPool pool;
    ERC20Mock poolToken;
    ERC20Mock defToken;
    ERC20Mock tokenB;

    int256 constant STARTING_X = 100e18; // starting ERC20
    int256 constant STARTING_Y = 50e18; // starting DEFTOKEN
    uint256 constant FEE = 997e15; //
    int256 constant MATH_PRECISION = 1e18;

    DefSwapPoolHandler handler;

    function setUp() public {
        defToken = new ERC20Mock();
        poolToken = new ERC20Mock();
        factory = new PoolFactory(address(defToken));
        pool = DefSwapPool(factory.createPool(address(poolToken)));

        // Create the initial x & y values for the pool
        poolToken.mint(address(this), uint256(STARTING_X));
        defToken.mint(address(this), uint256(STARTING_Y));
        poolToken.approve(address(pool), type(uint256).max);
        defToken.approve(address(pool), type(uint256).max);
        pool.deposit(
            uint256(STARTING_Y),
            uint256(STARTING_Y),
            uint256(STARTING_X),
            uint64(block.timestamp)
        );

        handler = new DefSwapPoolHandler(pool);

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = DefSwapPoolHandler.deposit.selector;
        selectors[1] = DefSwapPoolHandler
            .swapPoolTokenForDefTokensBasedOnInputDefTokens
            .selector;

        targetSelector(
            FuzzSelector({addr: address(handler), selectors: selectors})
        );
        targetContract(address(handler));
    }

    // Normal Invariant
    // x * y = k
    // x * y = (x + ∆x) * (y − ∆y)
    // x = Token Balance X
    // y = Token Balance Y
    // ∆x = Change of token balance X
    // ∆y = Change of token balance Y
    // β = (∆y / y)
    // α = (∆x / x)

    // Final invariant equation without fees:
    // ∆x = (β/(1-β)) * x
    // ∆y = (α/(1+α)) * y

    // Invariant with fees
    // ρ = fee (between 0 & 1, aka a percentage)
    // γ = (1 - p) (pronounced gamma)
    // ∆x = (β/(1-β)) * (1/γ) * x
    // ∆y = (αγ/1+αγ) * y
    function invariant_deltaXFollowsMath() public view {
        assertEq(handler.actualDeltaX(), handler.expectedDeltaX());
    }

    function invariant_deltaYFollowsMath() public view {
        assertEq(handler.actualDeltaY(), handler.expectedDeltaY());
    }
}
