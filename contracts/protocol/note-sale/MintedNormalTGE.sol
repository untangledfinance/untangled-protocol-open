// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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
        __Crowdsale__init();

        registry = _registry;
        pool = _pool;
        token = _token;
        currency = _currency;
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

    function getLongSaleTokenPrice(uint256 timestamp) public view returns (uint256) {
        if (!finalized) return (RATE_SCALING_FACTOR**2) / rate;
        else if (
            Configuration.NOTE_TOKEN_TYPE(INoteToken(token).noteTokenType()) == Configuration.NOTE_TOKEN_TYPE.JUNIOR
        ) {
            address sotTgeAddress = ISecuritizationPool(pool).tgeAddress();
            if (sotTgeAddress != address(0) && !FinalizableCrowdsale(sotTgeAddress).finalized())
                return (RATE_SCALING_FACTOR**2) / rate;
            return registry.getDistributionAssessor().calcTokenPrice(pool, token);
        } else {
            require(
                timeStartEarningInterest != 0,
                'MintedIncreasingInterestTGE: timeStartEarningInterest need to be setup'
            );
            return getPurchasePrice(interestRate, yield, timestamp - timeStartEarningInterest, termLengthInSeconds);
        }
    }

    function getLongSaleTokenAmount(uint256 currencyAmount) public view override returns (uint256) {
        return
            _getTokenAmount((currencyAmount * PURCHASE_PRICE_SCALING_FACTOR) / getLongSaleTokenPrice(block.timestamp));
    }

    function startNewRoundSale(
        uint256 openingTime,
        uint256 closingTime,
        uint256 rate,
        uint256 cap
    ) external whenNotPaused nonReentrant onlyRole(OWNER_ROLE) {
        _preValidateNewSaleRound();

        // call inner function for each extension
        newSaleRound(rate);
        newSaleRoundTime(openingTime, closingTime);
        setTotalCap(cap);
    }

    function _preValidateNewSaleRound() internal view {
        require(hasClosed() || totalCapReached(), 'MintedIncreasingInterestTGE: Previous round not closed');
    }
}
