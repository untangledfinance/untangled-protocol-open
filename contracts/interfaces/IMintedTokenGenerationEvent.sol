// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract IMintedTokenGenerationEvent {
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
