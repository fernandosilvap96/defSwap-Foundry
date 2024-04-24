Every DefSwapPool is paired with *DefToken*

### defToken, poolTokens, and liquidity tokens must always have the same ratio after the initial deposit

# The price considered in the DefSwapPool is the ratio of the initial deposit. For example: If the initial deposit is 1 DefToken and 100 poolTokens:
- Everytime that someone decide to swap, the price would be this ratio, if the user want to receive 1 DefToken he will need to deposit 100 poolTokens (He will receive 1 DefToken minus the LP_FEE)
