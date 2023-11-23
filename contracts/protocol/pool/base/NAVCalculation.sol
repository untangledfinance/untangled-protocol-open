// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import '../../../libraries/UntangledMath.sol';
import '../../../libraries/Configuration.sol';

import {RiskScore} from './types.sol';

contract NAVCalculation {
    uint256 public constant YEAR_LENGTH_IN_DAYS = 365;
    // All time units in seconds
    uint256 public constant MINUTE_LENGTH_IN_SECONDS = 60;
    uint256 public constant HOUR_LENGTH_IN_SECONDS = MINUTE_LENGTH_IN_SECONDS * 60;
    uint256 public constant DAY_LENGTH_IN_SECONDS = HOUR_LENGTH_IN_SECONDS * 24;
    uint256 public constant YEAR_LENGTH_IN_SECONDS = DAY_LENGTH_IN_SECONDS * YEAR_LENGTH_IN_DAYS;

    // To convert an encoded interest rate into its equivalent in percents,
    // divide it by INTEREST_RATE_SCALING_FACTOR_PERCENT -- e.g.
    //     10,000 => 1% interest rate
    uint256 public constant INTEREST_RATE_SCALING_FACTOR_PERCENT = 10 ** 4;
    uint256 public constant ONE_HUNDRED_PERCENT = 100 * INTEREST_RATE_SCALING_FACTOR_PERCENT;

    // struct RiskScore {
    //     uint32 daysPastDue;
    //     uint32 advanceRate;
    //     uint32 penaltyRate;
    //     uint32 interestRate;
    //     uint32 probabilityOfDefault;
    //     uint32 lossGivenDefault;
    //     uint32 writeOffAfterGracePeriod;
    //     uint32 gracePeriod;
    //     uint32 collectionPeriod;
    //     uint32 writeOffAfterCollectionPeriod;
    //     uint32 discountRate;
    // }

    /// @dev Calculate the expected present asset value
    /// @param principalAmount Principal amount of asset
    /// @param expectTimeEarnInterest Expected interest amount in expected repayment amount
    /// @param interestRate interest rate of LAT, or interest rate for SOT, or interest rate for JOT (always interest rate= 0)
    /// @param overdue overdue in seconds
    /// @param secondTillCashFlow time till expiration in seconds
    /// @param riskScore risk score applied
    /// @param assetPurpose asset purpose, pledge or sale
    /// @return expected present asset value
    function _calculateAssetValue(
        uint256 principalAmount,
        uint256 expectTimeEarnInterest,
        uint256 interestRate,
        uint256 overdue,
        uint256 secondTillCashFlow,
        RiskScore memory riskScore,
        Configuration.ASSET_PURPOSE assetPurpose
    ) internal pure returns (uint256) {
        uint256 morePercentDecimal = UntangledMath.ONE / INTEREST_RATE_SCALING_FACTOR_PERCENT / 100;
        uint256 totalDebtAmt = 0;

        if (assetPurpose == Configuration.ASSET_PURPOSE.PLEDGE) {
            interestRate = riskScore.interestRate;
            principalAmount = (principalAmount * riskScore.advanceRate) / ONE_HUNDRED_PERCENT;
        }

        totalDebtAmt =
            (principalAmount *
                UntangledMath.rpow(
                    UntangledMath.ONE + (interestRate * morePercentDecimal) / YEAR_LENGTH_IN_SECONDS,
                    expectTimeEarnInterest,
                    UntangledMath.ONE
                )) /
            UntangledMath.ONE;

        if (overdue > riskScore.gracePeriod) {
            totalDebtAmt =
                (totalDebtAmt *
                    UntangledMath.rpow(
                        UntangledMath.ONE + (interestRate * morePercentDecimal) / YEAR_LENGTH_IN_SECONDS,
                        riskScore.gracePeriod,
                        UntangledMath.ONE
                    )) /
                UntangledMath.ONE;

            uint256 penaltyRate = (interestRate * riskScore.penaltyRate) / ONE_HUNDRED_PERCENT;

            totalDebtAmt =
                (totalDebtAmt *
                    UntangledMath.rpow(
                        UntangledMath.ONE + (penaltyRate * morePercentDecimal) / YEAR_LENGTH_IN_SECONDS,
                        overdue - riskScore.gracePeriod,
                        UntangledMath.ONE
                    )) /
                UntangledMath.ONE;
            uint256 writeOff = riskScore.writeOffAfterGracePeriod;
            if (overdue > riskScore.collectionPeriod) writeOff = riskScore.writeOffAfterCollectionPeriod;

            totalDebtAmt = (totalDebtAmt * (ONE_HUNDRED_PERCENT - writeOff)) / ONE_HUNDRED_PERCENT;
        } else if (overdue > 0) {
            totalDebtAmt =
                (totalDebtAmt *
                    UntangledMath.rpow(
                        UntangledMath.ONE + (interestRate * morePercentDecimal) / YEAR_LENGTH_IN_SECONDS,
                        overdue,
                        UntangledMath.ONE
                    )) /
                UntangledMath.ONE;
        }

        uint256 creditRiskAdjustedExpCF = totalDebtAmt -
            ((totalDebtAmt * riskScore.probabilityOfDefault * expectTimeEarnInterest * riskScore.lossGivenDefault) /
                (YEAR_LENGTH_IN_SECONDS * ONE_HUNDRED_PERCENT ** 2));
        return
            (creditRiskAdjustedExpCF * UntangledMath.ONE) /
            UntangledMath.rpow(
                UntangledMath.ONE + (riskScore.discountRate * morePercentDecimal) / YEAR_LENGTH_IN_SECONDS,
                secondTillCashFlow,
                UntangledMath.ONE
            );
    }

    uint256[50] private __gap;
}
