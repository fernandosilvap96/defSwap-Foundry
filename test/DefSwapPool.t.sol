// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DefSwapPool} from "../src/PoolFactory.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract DefSwapPoolTest is Test {
    DefSwapPool pool;
    ERC20Mock poolToken;
    ERC20Mock defToken;

    address liquidityProvider = makeAddr("liquidityProvider");
    address user = makeAddr("user");

    function setUp() public {
        poolToken = new ERC20Mock();
        defToken = new ERC20Mock();
        pool = new DefSwapPool(
            address(poolToken),
            address(defToken),
            "LTokenA",
            "LA"
        );

        defToken.mint(liquidityProvider, 200e18);
        poolToken.mint(liquidityProvider, 200e18);

        defToken.mint(user, 10e18);
        poolToken.mint(user, 10e18);
    }

    function testDeposit() public {
        vm.startPrank(liquidityProvider);
        defToken.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));

        assertEq(pool.balanceOf(liquidityProvider), 100e18);
        assertEq(defToken.balanceOf(liquidityProvider), 100e18);
        assertEq(poolToken.balanceOf(liquidityProvider), 100e18);

        assertEq(defToken.balanceOf(address(pool)), 100e18);
        assertEq(poolToken.balanceOf(address(pool)), 100e18);
    }

    function testDepositSwap() public {
        vm.startPrank(liquidityProvider);
        defToken.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));
        vm.stopPrank();

        vm.startPrank(user);
        poolToken.approve(address(pool), 10e18);
        // After we swap, there will be ~110 tokenA, and ~91 deftoken
        // 100 * 100 = 10,000
        // 110 * ~91 = 10,000

        pool.swap(poolToken, 10e18, defToken, uint64(block.timestamp));
        assert(defToken.balanceOf(user) >= 9e18);
    }

    function testWithdraw() public {
        vm.startPrank(liquidityProvider);
        defToken.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));

        pool.approve(address(pool), 100e18);
        pool.withdraw(100e18, 100e18, 100e18, uint64(block.timestamp));

        assertEq(pool.totalSupply(), 0);
        assertEq(defToken.balanceOf(liquidityProvider), 200e18);
        assertEq(poolToken.balanceOf(liquidityProvider), 200e18);
    }

    function testCollectFees() public {
        vm.startPrank(liquidityProvider);
        defToken.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));
        vm.stopPrank();

        vm.startPrank(user);
        poolToken.approve(address(pool), 10e18);
        pool.swap(poolToken, 10e18, defToken, uint64(block.timestamp));
        vm.stopPrank();

        vm.startPrank(liquidityProvider);
        pool.approve(address(pool), 100e18);
        pool.withdraw(100e18, 90e18, 100e18, uint64(block.timestamp));
        assertEq(pool.totalSupply(), 0);
        assert(
            defToken.balanceOf(liquidityProvider) +
                poolToken.balanceOf(liquidityProvider) >
                400e18
        );
    }
}
