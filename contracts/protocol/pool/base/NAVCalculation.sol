// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '../../../libraries/UntangledMath.sol';
import '../../../libraries/Configuration.sol';

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
    uint256 public constant INTEREST_RATE_SCALING_FACTOR_PERCENT = 10**4;
    uint256 public constant ONE_HUNDRED_PERCENT = 100 * INTEREST_RATE_SCALING_FACTOR_PERCENT;

    struct RiskScore {
        uint32 daysPastDue;
        uint32 advanceRate;
        uint32 penaltyRate;
        uint32 interestRate;
        uint32 probabilityOfDefault;
        uint32 lossGivenDefault;
        uint32 writeOffAfterGracePeriod;
        uint32 gracePeriod;
        uint32 collectionPeriod;
        uint32 writeOffAfterCollectionPeriod;
    }

    function _calculateAssetValue(
        uint256 totalDebtAmt,
        uint256 interestRate,
        uint256 overdue,
        RiskScore memory riskScore,
        Configuration.ASSET_PURPOSE assetPurpose
    ) internal pure returns (uint256) {
        uint256 morePercentDecimal = UntangledMath.ONE / INTEREST_RATE_SCALING_FACTOR_PERCENT / 100;

        if (assetPurpose == Configuration.ASSET_PURPOSE.PLEDGE) interestRate = riskScore.interestRate;

        totalDebtAmt = (totalDebtAmt * riskScore.advanceRate) / ONE_HUNDRED_PERCENT;

        if (overdue > riskScore.gracePeriod) {
            totalDebtAmt =
                (totalDebtAmt *
                    (UntangledMath.ONE +
                        UntangledMath.rpow(
                            (interestRate * morePercentDecimal) / YEAR_LENGTH_IN_SECONDS,
                            riskScore.gracePeriod,
                            UntangledMath.ONE
                        ))) /
                UntangledMath.ONE;

            uint256 penaltyRate = (interestRate * riskScore.penaltyRate) / ONE_HUNDRED_PERCENT;

            totalDebtAmt =
                (totalDebtAmt *
                    (UntangledMath.ONE +
                        UntangledMath.rpow(
                            (penaltyRate * morePercentDecimal) / YEAR_LENGTH_IN_SECONDS,
                            overdue - riskScore.gracePeriod,
                            UntangledMath.ONE
                        ))) /
                UntangledMath.ONE;
            uint256 writeOff = riskScore.writeOffAfterGracePeriod;
            if (overdue > riskScore.collectionPeriod) writeOff = riskScore.writeOffAfterCollectionPeriod;

            totalDebtAmt = (totalDebtAmt * (ONE_HUNDRED_PERCENT - writeOff)) / ONE_HUNDRED_PERCENT;
        } else if (overdue > 0) {
            totalDebtAmt =
                (totalDebtAmt *
                    (UntangledMath.ONE +
                        UntangledMath.rpow(
                            (interestRate * morePercentDecimal) / YEAR_LENGTH_IN_SECONDS,
                            overdue,
                            UntangledMath.ONE
                        ))) /
                UntangledMath.ONE;
        }

        return
            totalDebtAmt -
            ((totalDebtAmt * riskScore.probabilityOfDefault * riskScore.lossGivenDefault) / ONE_HUNDRED_PERCENT**2);
    }

    uint256[50] private __gap;
}
