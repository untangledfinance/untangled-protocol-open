// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import '../storage/Registry.sol';
import '../base/UntangledBase.sol';

abstract contract IMintedIncreasingInterestTGE is UntangledBase {
    function initialize(
        Registry _registry,
        address _pool,
        address _token,
        address _currency,
        bool _isLongSale
    ) public virtual;

    bool public finalized;

    uint256 public currencyRaised;

    function setupLongSale(
        uint256 interestRate,
        uint256 termLengthInSeconds,
        uint256 timeStartEarningInterest
    ) public virtual;

    function buyTokens(
        address payee,
        address beneficiary,
        uint256 currencyAmount
    ) external virtual returns (uint256);
}
