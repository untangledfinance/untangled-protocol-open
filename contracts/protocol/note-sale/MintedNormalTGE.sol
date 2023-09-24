// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

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
    uint256 public initialJOTAmount;

    uint32 public pickedInterest;

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
    /// @param openingTime_ Define when the sale should start
    /// @param closingTime_ Define when the sale should end
    /// @param cap_ Target amount of raised currency
    function startNewRoundSale(
        uint256 openingTime_,
        uint256 closingTime_,
        uint256 rate_,
        uint256 cap_
    ) external whenNotPaused {
        require(hasRole(OWNER_ROLE, _msgSender()) || _msgSender() == address(registry.getSecuritizationManager()), "MintedNormalTGE: Caller must be owner or pool");
        _preValidateNewSaleRound();

        // call inner function for each extension
        _newSaleRound(rate_);
        newSaleRoundTime(openingTime_, closingTime_);
        _setTotalCap(cap_);
    }

    /// @notice Setup initial amount currency raised for JOT condition
    /// @param _initialAmountJOT Expected minimum amount of JOT before SOT start
    function setInitialAmountJOT(
        uint256 _initialAmountJOT
    ) external whenNotPaused {
        require(hasRole(OWNER_ROLE, _msgSender()) || _msgSender() == address(registry.getSecuritizationManager()), "MintedNormalTGE: Caller must be owner or pool");
        require(initialJOTAmount < totalCap, "MintedNormalTGE: Initial JOT amount must be less than total cap");
        initialJOTAmount = _initialAmountJOT;
    }

    /// @dev Validates that the previous sale round is closed and the time interval for increasing interest is greater than zero
    function _preValidateNewSaleRound() internal view {
        require(hasClosed() || totalCapReached(), 'MintedIncreasingInterestTGE: Previous round not closed');
    }

    function _finalization() internal override {
        super._finalization();

        pickedInterest = uint32(interestRate);
    }

    function buyTokens(address payee, address beneficiary, uint256 currencyAmount) public override(IMintedTGE, Crowdsale)  returns (uint256) {
        return Crowdsale.buyTokens(payee, beneficiary, currencyAmount);
    }

    uint256[45] private __gap;
}
