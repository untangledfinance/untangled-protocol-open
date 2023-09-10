// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../../../libraries/UntangledMath.sol';

contract Interest {
    /// @dev Represents the number of days in a year
    uint256 public constant YEAR_LENGTH_IN_DAYS = 365;
    // All time units in seconds

    /// @dev Represents the number of seconds in a minute
    uint256 public constant MINUTE_LENGTH_IN_SECONDS = 60;
    /// @dev Represents the number of seconds in an hour
    uint256 public constant HOUR_LENGTH_IN_SECONDS = MINUTE_LENGTH_IN_SECONDS * 60;
    /// @dev Represents the number of seconds in a day
    uint256 public constant DAY_LENGTH_IN_SECONDS = HOUR_LENGTH_IN_SECONDS * 24;
    /// @dev Represents the number of seconds in a year
    uint256 public constant YEAR_LENGTH_IN_SECONDS = DAY_LENGTH_IN_SECONDS * YEAR_LENGTH_IN_DAYS;

    // To convert an encoded interest rate into its equivalent in percents,
    // divide it by INTEREST_RATE_SCALING_FACTOR_PERCENT -- e.g.
    //     10,000 => 1% interest rate
    /// @dev A constant used to convert an encoded interest rate into its equivalent in percentage.
    /// To convert an encoded interest rate to a percentage, divide it by this scaling factor
    uint256 public constant INTEREST_RATE_SCALING_FACTOR_PERCENT = 10**4;

    // To convert an encoded interest rate into its equivalent multiplier
    // (for purposes of calculating total interest), divide it by INTEREST_RATE_SCALING_FACTOR_PERCENT -- e.g.
    //     10,000 => 0.01 interest multiplier
    /// @dev A constant used to convert an encoded interest rate into its equivalent multiplier for calculating total interest.
    /// To convert an encoded interest rate to an interest multiplier, divide it by this scaling factor
    uint256 public constant INTEREST_RATE_SCALING_FACTOR_MULTIPLIER = INTEREST_RATE_SCALING_FACTOR_PERCENT * 100;

    /// @notice Calculates the interest amount for a given principal amount, annual interest rate, start term timestamp, and current timestamp
    function chargeInterest(
        uint256 principalAmount,
        uint256 annualInterestRate,
        uint256 startTermTimestamp,
        uint256 timestamp
    ) public pure returns (uint256) {
        return _calculateInterestAmountToTimestamp(principalAmount, annualInterestRate, startTermTimestamp, timestamp);
    }

    /// @notice Calculates the interest amount for lending based on the current principal amount, annual interest rate,
    /// start term timestamp, and current timestamp
    function chargeLendingInterest(
        uint256 _currentPrincipalAmount,
        uint256 _annualInterestRate,
        uint256 _startTermTimestamp,
        uint256 _timestamp
    ) public pure returns (uint256) {
        return
            _calculateInterestAmountToTimestamp(
                _currentPrincipalAmount,
                _annualInterestRate,
                _startTermTimestamp,
                _timestamp
            );
    }

    // Calculate interest amount of fixed amount principal
    /// @dev Calculates the interest amount for a fixed amount principal until a specified timestamp
    function _calculateInterestAmountToTimestamp(
        uint256 _principalAmount,
        uint256 _annualInterestRate,
        uint256 _startTermTimestamp,
        uint256 _timestamp
    ) internal pure returns (uint256) {
        if (_timestamp <= _startTermTimestamp) {
            return 0;
        }
        uint256 elapseTimeFromStart = _timestamp - _startTermTimestamp;

        return _calculateInterestForDuration(_principalAmount, _annualInterestRate, elapseTimeFromStart);
    }

    // Calculate interest amount Debtor need to pay until current date
    /// @dev Calculates the interest amount for a current principal amount, considering the previously paid interest amount
    function _calculateInterestAmountToTimestamp(
        uint256 _currentPrincipalAmount,
        uint256 _paidInterestAmount,
        uint256 _annualInterestRate,
        uint256 _startTermTimestamp,
        uint256 _lastRepayTimestamp,
        uint256 _timestamp
    ) internal pure returns (uint256) {
        if (_timestamp <= _startTermTimestamp) {
            return 0;
        }
        uint256 interest = 0;
        uint256 elapseTimeFromLastRepay = _timestamp - _lastRepayTimestamp;
        uint256 elapseTimeFromStart = _timestamp - _startTermTimestamp;

        if (_paidInterestAmount > 0) {
            // Has made at least 1 repayment
            interest = _calculateInterestForDuration(
                _currentPrincipalAmount,
                _annualInterestRate,
                elapseTimeFromLastRepay
            );
        } else {
            // Haven't made any repayment
            interest = _calculateInterestForDuration(_currentPrincipalAmount, _annualInterestRate, elapseTimeFromStart);
        }

        return interest;
    }

    // Calculate interest amount for a duration with specific Principal amount
    /// @dev Calculates the interest amount for a specified duration with a specific principal amount
    function _calculateInterestForDuration(
        uint256 _principalAmount,
        uint256 _interestRate,
        uint256 _durationLengthInSec
    ) internal pure returns (uint256) {
        return
            (_principalAmount *
                UntangledMath.rpow(
                    UntangledMath.ONE +
                        ((_interestRate * (UntangledMath.ONE / INTEREST_RATE_SCALING_FACTOR_PERCENT / 100)) /
                            YEAR_LENGTH_IN_SECONDS),
                    _durationLengthInSec,
                    UntangledMath.ONE
                )) /
            UntangledMath.ONE -
            _principalAmount;
    }
}
