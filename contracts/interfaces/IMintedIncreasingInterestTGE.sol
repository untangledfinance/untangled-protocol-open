// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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

    /// @notice initialize long sale settings
    function setupLongSale(
        uint256 interestRate,
        uint256 termLengthInSeconds,
        uint256 timeStartEarningInterest
    ) public virtual;

    ///@notice investor bids for SOT/JOT token. Paid by pool's currency
    function buyTokens(
        address payee,
        address beneficiary,
        uint256 currencyAmount
    ) external virtual returns (uint256);
}
