// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './crowdsale/IncreasingInterestCrowdsale.sol';
import './base/LongSaleInterest.sol';

contract MintedIncreasingInterestTGE is IncreasingInterestCrowdsale, LongSaleInterest {
    using ConfigHelper for Registry;

    bool public longSale;
    uint256 public timeStartEarningInterest;
    uint256 public termLengthInSeconds;
    uint256 public interestRate;
    uint256 public yield;

    function initialize(
        Registry _registry,
        address _pool,
        address _token,
        address _currency,
        bool _longSale
    ) public initializer {
        __Crowdsale__init(_registry, _pool, _token, _currency);

        longSale = _longSale;
    }

    /// @inheritdoc Crowdsale
    function isLongSale() public view override returns (bool) {
        return longSale;
    }

    /// @dev Sets the yield variable to the specified value
    function setYield(uint256 _yield) public whenNotPaused onlyRole(OWNER_ROLE) {
        yield = _yield;
    }

    function setupLongSale(
        uint256 _interestRate,
        uint256 _termLengthInSeconds,
        uint256 _timeStartEarningInterest
    ) public whenNotPaused nonReentrant securitizationPoolRestricted {
        if (isLongSale()) {
            interestRate = _interestRate;
            timeStartEarningInterest = _timeStartEarningInterest;
            termLengthInSeconds = _termLengthInSeconds;
            yield = _interestRate;
        }
    }

    /// @notice Calculate token price
    /// @dev This sale is for SOT. So the function return SOT token price
    function getTokenPrice() public view returns (uint256) {
        return registry.getDistributionAssessor().getSOTTokenPrice(
            address(pool)
        );
    }

    /// @notice Get amount of token can receive from an amount of currency
    function getTokenAmount(uint256 currencyAmount) public view override returns (uint256) {
        return currencyAmount / getTokenPrice();
    }

    /// @notice Setup a new round sale for note token
    /// @param openingTime Define when the sale should start
    /// @param closingTime Define when the sale should end
    /// @param cap Target amount of raised currency
    function startNewRoundSale(
        uint256 openingTime,
        uint256 closingTime,
        uint256 rate,
        uint256 cap
    ) external whenNotPaused nonReentrant {
        require(hasRole(OWNER_ROLE, _msgSender()) || _msgSender() == address(registry.getSecuritizationManager()), "MintedIncreasingInterestTGE: Caller must be owner or pool");
        _preValidateNewSaleRound();

        // call inner function for each extension
        _newSaleRound(rate);
        newSaleRoundTime(openingTime, closingTime);
        _setTotalCap(cap);
    }

    /// @dev Validates that the previous sale round is closed and the time interval for increasing interest is greater than zero
    function _preValidateNewSaleRound() internal view {
        require(hasClosed() || totalCapReached(), 'MintedIncreasingInterestTGE: Previous round not closed');
        require(timeInterval > 0, 'MintedIncreasingInterestTGE: Time interval increasing interest is 0');
    }
}
