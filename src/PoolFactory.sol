// SPDX-License-Identifier: GNU General Public License v3.0
pragma solidity 0.8.20;

import {DefSwapPool} from "./DefSwapPool.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract PoolFactory {
    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/
    error PoolFactory__PoolAlreadyExists(address tokenAddress);
    error PoolFactory__PoolDoesNotExist(address tokenAddress);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    mapping(address token => address pool) private s_pools;
    mapping(address pool => address token) private s_tokens;

    address private immutable i_defToken;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event PoolCreated(address tokenAddress, address poolAddress);

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(address defToken) {
        i_defToken = defToken;
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function createPool(address tokenAddress) external returns (address) {
        if (s_pools[tokenAddress] != address(0)) {
            revert PoolFactory__PoolAlreadyExists(tokenAddress);
        }
        string memory liquidityTokenName = string.concat(
            "DefSwapPool ",
            IERC20(tokenAddress).name()
        );
        string memory liquidityTokenSymbol = string.concat(
            "ds",
            IERC20(tokenAddress).symbol()
        );
        DefSwapPool defSwapPool = new DefSwapPool(
            tokenAddress,
            i_defToken,
            liquidityTokenName,
            liquidityTokenSymbol
        );
        s_pools[tokenAddress] = address(defSwapPool);
        s_tokens[address(defSwapPool)] = tokenAddress;
        emit PoolCreated(tokenAddress, address(defSwapPool));
        return address(defSwapPool);
    }

    /*//////////////////////////////////////////////////////////////
                   EXTERNAL AND PUBLIC VIEW AND PURE
    //////////////////////////////////////////////////////////////*/
    function getPool(address tokenAddress) external view returns (address) {
        return s_pools[tokenAddress];
    }

    function getToken(address pool) external view returns (address) {
        return s_tokens[pool];
    }

    function getDefToken() external view returns (address) {
        return i_defToken;
    }
}
