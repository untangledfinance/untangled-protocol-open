// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../../../libraries/UntangledMath.sol';

contract LongSaleInterest {
    uint256 public constant YEAR_LENGTH_IN_DAYS = 365;
    // All time units in seconds
    uint256 public constant MINUTE_LENGTH_IN_SECONDS = 60;
    uint256 public constant HOUR_LENGTH_IN_SECONDS = MINUTE_LENGTH_IN_SECONDS * 60;
    uint256 public constant DAY_LENGTH_IN_SECONDS = HOUR_LENGTH_IN_SECONDS * 24;
    uint256 public constant YEAR_LENGTH_IN_SECONDS = DAY_LENGTH_IN_SECONDS * YEAR_LENGTH_IN_DAYS;

    // To convert an encoded interest rate into its equivalent in percents,
    // divide it by INTEREST_RATE_SCALING_FACTOR_PERCENT -- e.g.
    //     10,000 => 1% interest rate
    uint256 public constant INTEREST_RATE_SCALING_FACTOR_PERCENT = 10**4;
    uint256 public constant PURCHASE_PRICE_SCALING_FACTOR = 10**4;

    function getPurchasePrice(
        uint256 _interestRate,
        uint256 _yield,
        uint256 _durationLengthInSec,
        uint256 _termLengthInSeconds
    ) public pure returns (uint256) {
        uint256 moreDecimal = UntangledMath.ONE / INTEREST_RATE_SCALING_FACTOR_PERCENT / 100;
        _interestRate = _interestRate * moreDecimal;
        _yield = _yield * moreDecimal;

        uint256 pricipalWithInterestInPercent = UntangledMath.ONE + _interestRate / YEAR_LENGTH_IN_SECONDS;

        uint256 pricipalWithYieldInPercent = UntangledMath.ONE + _yield / YEAR_LENGTH_IN_SECONDS;

        uint256 durationToEndTerm = _termLengthInSeconds - _durationLengthInSec;
        return
            (UntangledMath.rpow(pricipalWithInterestInPercent, _termLengthInSeconds, UntangledMath.ONE) *
                PURCHASE_PRICE_SCALING_FACTOR) /
            UntangledMath.rpow(pricipalWithYieldInPercent, durationToEndTerm, UntangledMath.ONE);
    }
}
