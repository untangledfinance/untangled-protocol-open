// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../storage/Registry.sol';

interface IMintedTGE {
    
    event YieldUpdated(uint256 newYield);
    event SetupLongSale(uint256 interestRate, uint256 termLengthInSeconds, uint256 timeStartEarningInterest);

    function initialize(
        Registry _registry,
        address _pool,
        address _token,
        address _currency,
        bool _isLongSale
    ) external;

    /// @notice initialize long sale settings
    function setupLongSale(
        uint256 interestRate,
        uint256 termLengthInSeconds,
        uint256 timeStartEarningInterest
    ) external;

    ///@notice investor bids for SOT/JOT token. Paid by pool's currency
    function buyTokens(address payee, address beneficiary, uint256 currencyAmount) external returns (uint256);
}
