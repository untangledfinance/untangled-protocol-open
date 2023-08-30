// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../../../libraries/UntangledMath.sol';

contract LongSaleInterest {
    /// @dev represents the number of days in a year
    uint256 public constant YEAR_LENGTH_IN_DAYS = 365;
    // All time units in seconds
    /// @dev represents the number of seconds in a minute
    uint256 public constant MINUTE_LENGTH_IN_SECONDS = 60;
    /// @dev represents the number of seconds in an hour
    uint256 public constant HOUR_LENGTH_IN_SECONDS = MINUTE_LENGTH_IN_SECONDS * 60;
    /// @dev represents the number of seconds in a day
    uint256 public constant DAY_LENGTH_IN_SECONDS = HOUR_LENGTH_IN_SECONDS * 24;
    /// @dev represents the number of seconds in a year
    uint256 public constant YEAR_LENGTH_IN_SECONDS = DAY_LENGTH_IN_SECONDS * YEAR_LENGTH_IN_DAYS;

    // To convert an encoded interest rate into its equivalent in percents,
    // divide it by INTEREST_RATE_SCALING_FACTOR_PERCENT -- e.g.
    //     10,000 => 1% interest rate
    /// @dev A constant used to convert an encoded interest rate into its equivalent in percentage.
    /// To convert an encoded interest rate to a percentage, divide it by this scaling factor
    uint256 public constant INTEREST_RATE_SCALING_FACTOR_PERCENT = 10**4;
    /// @dev represents the scaling factor for the purchase price calculation
    uint256 public constant PURCHASE_PRICE_SCALING_FACTOR = 10**4;

}
