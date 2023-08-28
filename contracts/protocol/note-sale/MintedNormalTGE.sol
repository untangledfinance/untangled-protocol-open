// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import './base/LongSaleInterest.sol';
import "../../libraries/ConfigHelper.sol";
import './crowdsale/FinalizableCrowdsale.sol';

contract MintedNormalTGE is FinalizableCrowdsale, LongSaleInterest {
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

    function isLongSale() public view override returns (bool) {
        return longSale;
    }

    function setYield(uint256 _yield) public whenNotPaused nonReentrant onlyRole(OWNER_ROLE) {
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

    function getTokenPrice() public view returns (uint256) {
        return registry.getDistributionAssessor().getJOTTokenPrice(
            ISecuritizationPool(pool)
        );
    }

    function getTokenAmount(uint256 currencyAmount) public view override returns (uint256) {
        return currencyAmount / getTokenPrice();
    }

    function startNewRoundSale(
        uint256 openingTime,
        uint256 closingTime,
        uint256 rate,
        uint256 cap
    ) external whenNotPaused nonReentrant {
        require(hasRole(OWNER_ROLE, _msgSender()) || _msgSender() == address(registry.getSecuritizationManager()), "MintedNormalTGE: Caller must be owner or pool");
        _preValidateNewSaleRound();

        // call inner function for each extension
        _newSaleRound(rate);
        newSaleRoundTime(openingTime, closingTime);
        _setTotalCap(cap);
    }

    function _preValidateNewSaleRound() internal view {
        require(hasClosed() || totalCapReached(), 'MintedIncreasingInterestTGE: Previous round not closed');
    }
}
