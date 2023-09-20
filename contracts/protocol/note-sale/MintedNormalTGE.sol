// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './base/LongSaleInterest.sol';
import "../../libraries/ConfigHelper.sol";
import './crowdsale/FinalizableCrowdsale.sol';
import '../../interfaces/IMintedTGE.sol';

/// @title MintedNormalTGE
/// @author Untangled Team
/// @dev Note sale for JOT
contract MintedNormalTGE is IMintedTGE, FinalizableCrowdsale, LongSaleInterest {
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
        emit YieldUpdated(_yield);
    }

    function setupLongSale(
        uint256 _interestRate,
        uint256 _termLengthInSeconds,
        uint256 _timeStartEarningInterest
    ) public whenNotPaused securitizationPoolRestricted {
        if (isLongSale()) {
            interestRate = _interestRate;
            timeStartEarningInterest = _timeStartEarningInterest;
            termLengthInSeconds = _termLengthInSeconds;
            yield = _interestRate;
            emit SetupLongSale(interestRate, termLengthInSeconds, timeStartEarningInterest);
            emit YieldUpdated(yield);
        }
    }

    function getTokenPrice() public view returns (uint256) {
        return registry.getDistributionAssessor().getJOTTokenPrice(
            ISecuritizationPool(pool)
        );
    }

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
    ) external whenNotPaused {
        require(hasRole(OWNER_ROLE, _msgSender()) || _msgSender() == address(registry.getSecuritizationManager()), "MintedNormalTGE: Caller must be owner or pool");
        _preValidateNewSaleRound();

        // call inner function for each extension
        _newSaleRound(rate);
        newSaleRoundTime(openingTime, closingTime);
        _setTotalCap(cap);
    }

    /// @dev Validates that the previous sale round is closed and the time interval for increasing interest is greater than zero
    function _preValidateNewSaleRound() internal view {
        require(hasClosed() || totalCapReached(), 'MintedIncreasingInterestTGE: Previous round not closed');
    }

    function buyTokens(address payee, address beneficiary, uint256 currencyAmount) public override(IMintedTGE, Crowdsale)  returns (uint256) {
        return Crowdsale.buyTokens(payee, beneficiary, currencyAmount);
    }
}
