// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './FinalizableCrowdsale.sol';

abstract contract IncreasingInterestCrowdsale is FinalizableCrowdsale {
    using ConfigHelper for Registry;
    uint32 public initialInterest;
    uint32 public finalInterest;
    uint32 public timeInterval;
    uint32 public amountChangeEachInterval;

    uint32 public pickedInterest;

    function setInterestRange(
        uint32 _initialInterest,
        uint32 _finalInterest,
        uint32 _timeInterval,
        uint32 _amountChangeEachInterval
    ) public whenNotPaused nonReentrant {
        require(hasRole(OWNER_ROLE, _msgSender()) || _msgSender() == address(registry.getSecuritizationManager()), "IncreasingInterestCrowdsale: Caller must be owner or pool");
        require(!hasStarted, 'IncreasingInterestCrowdsale: sale already started');
        require(
            _initialInterest <= _finalInterest,
            'IncreasingInterestCrowdsale: initial interest is not less than final interest'
        );
        require(_timeInterval > 0, 'IncreasingInterestCrowdsale: time interval is 0');

        initialInterest = _initialInterest;
        finalInterest = _finalInterest;
        timeInterval = _timeInterval;
        amountChangeEachInterval = _amountChangeEachInterval;
    }

    function getCurrentInterest() public view returns (uint32) {
        if (block.timestamp < openingTime) {
            return 0;
        }

        // solhint-disable-next-line not-rely-on-time
        uint256 elapsedTime = block.timestamp - openingTime;
        uint256 numberInterval = elapsedTime / timeInterval;

        uint32 currentInterest = uint32(amountChangeEachInterval * numberInterval + initialInterest);

        if (currentInterest > finalInterest) {
            return finalInterest;
        } else {
            return currentInterest;
        }
    }

    function _finalization() internal override {
        super._finalization();

        pickedInterest = getCurrentInterest();
        ISecuritizationPool(pool).setInterestRateForSOT(pickedInterest);
    }

    function _preValidatePurchase(
        address beneficiary,
        uint256 currencyAmount,
        uint256 tokenAmount
    ) internal view override {
        super._preValidatePurchase(beneficiary, currencyAmount, tokenAmount);
        require(timeInterval > 0, 'IncreasingInterestCrowdsale: time interval not set');
    }
}
