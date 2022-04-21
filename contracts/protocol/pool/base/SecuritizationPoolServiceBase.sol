// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../../../base/UntangledBase.sol';
import '../../../interfaces/ISecuritizationPool.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '../../../libraries/ConfigHelper.sol';

contract SecuritizationPoolServiceBase is UntangledBase {
    Registry public registry;

    function initialize(Registry _registry) public initializer {
        __UntangledBase__init(_msgSender());

        registry = _registry;
    }

    function convertTokenValueToCurrencyAmount(
        address pool,
        address tokenAddress,
        uint256 tokenValue
    ) internal view returns (uint256) {
        uint256 currencyDecimals = ERC20(ISecuritizationPool(pool).underlyingCurrency()).decimals();
        uint256 tokenDecimals = ERC20(tokenAddress).decimals();

        return
            currencyDecimals > tokenDecimals
                ? tokenValue * (10**currencyDecimals - tokenDecimals)
                : tokenValue / (10**tokenDecimals - currencyDecimals);
    }

    function convertCurrencyAmountToTokenValue(
        address pool,
        address tokenAddress,
        uint256 currencyAmount
    ) internal view returns (uint256) {
        uint256 currencyDecimals = ERC20(ISecuritizationPool(pool).underlyingCurrency()).decimals();
        uint256 tokenDecimals = ERC20(tokenAddress).decimals();

        return
            currencyDecimals > tokenDecimals
                ? currencyAmount / (10**currencyDecimals - tokenDecimals)
                : currencyAmount * (10**tokenDecimals - currencyDecimals);
    }
}
