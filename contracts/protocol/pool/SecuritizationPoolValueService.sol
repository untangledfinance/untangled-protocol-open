// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/interfaces/IERC20.sol';
import '../../interfaces/INoteToken.sol';
import '../../interfaces/ISecuritizationPool.sol';
import './base/NAVCalculation.sol';
import './base/SecuritizationPoolServiceBase.sol';
import '../../interfaces/ICrowdSale.sol';

// import '../../libraries/UntangledMath.sol';

contract SecuritizationPoolValueService is
    SecuritizationPoolServiceBase,
    NAVCalculation,
    ISecuritizationPoolValueService
{
    using ConfigHelper for Registry;

    function getPresentValueWithNAVCalculation(
        address poolAddress,
        uint256 totalDebt,
        uint256 interestRate,
        uint256 riskScoreIdx, // riskScoreIdx should be reduced 1 to be able to use because 0 means no specific riskScore
        uint256 overdue,
        Configuration.ASSET_PURPOSE assetPurpose
    ) private view returns (uint256) {
        uint256 riskScoresLength = ISecuritizationPool(poolAddress).getRiskScoresLength();
        bool hasValidRiskScore = riskScoresLength > 0;
        if (hasValidRiskScore) {
            if (riskScoreIdx == 0) (hasValidRiskScore, riskScoreIdx) = getAssetRiskScoreIdx(poolAddress, overdue);
            else riskScoreIdx = riskScoreIdx > riskScoresLength ? riskScoresLength - 1 : riskScoreIdx - 1;
        }
        if (!hasValidRiskScore) return totalDebt;
        RiskScore memory riskscore = getRiskScoreByIdx(poolAddress, riskScoreIdx);
        return calculateAssetValue(totalDebt, interestRate, overdue, riskscore, assetPurpose);
    }

    function getExpectedAssetValue(
        address poolAddress,
        address tokenAddress,
        uint256 tokenId,
        uint256 timestamp
    ) public view returns (uint256) {
        IUntangledERC721 loanAssetToken = IUntangledERC721(tokenAddress);
        uint256 expirationTimestamp = loanAssetToken.getExpirationTimestamp(tokenId);

        uint256 overdue = timestamp > expirationTimestamp ? timestamp - expirationTimestamp : 0;
        uint256 totalDebt = loanAssetToken.getTotalExpectedRepaymentValue(tokenId, expirationTimestamp);

        uint256 presentValue = getPresentValueWithNAVCalculation(
            poolAddress,
            totalDebt,
            loanAssetToken.getInterestRate(tokenId),
            loanAssetToken.getRiskScore(tokenId),
            overdue,
            loanAssetToken.getAssetPurpose(tokenId)
        );

        if (timestamp < expirationTimestamp) {
            totalDebt = loanAssetToken.getTotalExpectedRepaymentValue(tokenId, timestamp);
        }

        return presentValue < totalDebt ? presentValue : totalDebt;
    }

    function getExpectedAssetValues(
        address poolAddress,
        address[] calldata tokenAddresses,
        uint256[] calldata tokenIds,
        uint256 timestamp
    ) external view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](tokenIds.length);
        for (uint256 i; i < tokenIds.length; i++) {
            balances[i] = getExpectedAssetValue(poolAddress, tokenAddresses[i], tokenIds[i], timestamp);
        }
        return balances;
    }

    function getAssetInterestRate(
        address poolAddress,
        address tokenAddress,
        uint256 tokenId,
        uint256 timestamp
    ) public view returns (uint256) {
        IUntangledERC721 loanAssetToken = IUntangledERC721(tokenAddress);
        uint256 interestRate = loanAssetToken.getInterestRate(tokenId);

        if (loanAssetToken.getAssetPurpose(tokenId) == Configuration.ASSET_PURPOSE.PLEDGE) {
            uint256 riskScoresLength = ISecuritizationPool(poolAddress).getRiskScoresLength();

            bool hasValidRiskScore = riskScoresLength > 0;
            if (hasValidRiskScore) {
                uint256 riskScoreIdx = loanAssetToken.getRiskScore(tokenId);

                if (riskScoreIdx == 0) {
                    uint256 expirationTimestamp = loanAssetToken.getExpirationTimestamp(tokenId);
                    uint256 overdue = timestamp > expirationTimestamp ? timestamp - expirationTimestamp : 0;
                    (hasValidRiskScore, riskScoreIdx) = getAssetRiskScoreIdx(poolAddress, overdue);
                } else riskScoreIdx = riskScoreIdx > riskScoresLength ? riskScoresLength - 1 : riskScoreIdx - 1;

                if (hasValidRiskScore) {
                    RiskScore memory riskscore = getRiskScoreByIdx(poolAddress, riskScoreIdx);
                    return riskscore.interestRate;
                }
            }
        }

        return interestRate;
    }

    function getAssetInterestRates(
        address poolAddress,
        address[] calldata tokenAddresses,
        uint256[] calldata tokenIds,
        uint256 timestamp
    ) external view returns (uint256[] memory) {
        uint256[] memory interestRates = new uint256[](tokenIds.length);
        for (uint256 i; i < tokenIds.length; i++) {
            interestRates[i] = getAssetInterestRate(poolAddress, tokenAddresses[i], tokenIds[i], timestamp);
        }
        return interestRates;
    }

    function getExpectedERC20AssetValue(
        address poolAddress,
        address assetPoolAddress,
        address tokenAddress,
        uint256 interestRate,
        uint256 timestamp
    ) public view returns (uint256) {
        uint256 expirationTimestamp = ISecuritizationPool(assetPoolAddress).openingBlockTimestamp() +
            ISecuritizationPool(assetPoolAddress).termLengthInSeconds();

        uint256 overdue = timestamp > expirationTimestamp ? timestamp - expirationTimestamp : 0;

        uint256 totalDebt = registry.getDistributionAssessor().calcCorrespondingTotalAssetValue(
            tokenAddress,
            poolAddress,
            timestamp
        );

        uint256 presentValue = getPresentValueWithNAVCalculation(
            poolAddress,
            totalDebt,
            interestRate,
            0,
            overdue,
            Configuration.ASSET_PURPOSE.SALE
        );

        if (timestamp < expirationTimestamp) {
            totalDebt = registry.getDistributionAssessor().calcCorrespondingTotalAssetValue(
                tokenAddress,
                poolAddress,
                timestamp
            );
        }

        return
            convertTokenValueToCurrencyAmount(
                poolAddress,
                tokenAddress,
                presentValue < totalDebt ? presentValue : totalDebt
            );
    }

    function getExpectedAssetsValue(
        address poolAddress,
        uint256 timestamp
    ) external view returns (uint256 expectedAssetsValue) {
        expectedAssetsValue = 0;
        ISecuritizationPool securitizationPool = ISecuritizationPool(poolAddress);

        for (uint256 i = 0; i < securitizationPool.getNFTAssetsLength(); ++i) {
            (address assetTokenAddress, uint256 assetTokenId) = securitizationPool.nftAssets(i);
            expectedAssetsValue =
                expectedAssetsValue +
                getExpectedAssetValue(poolAddress, assetTokenAddress, assetTokenId, timestamp);
        }
        for (uint256 i = 0; i < securitizationPool.getTokenAssetAddressesLength(); ++i) {
            address tokenAddress = securitizationPool.tokenAssetAddresses(i);
            INoteToken notesToken = INoteToken(tokenAddress);
            if (notesToken.balanceOf(poolAddress) > 0) {
                expectedAssetsValue =
                    expectedAssetsValue +
                    getExpectedERC20AssetValue(
                        poolAddress,
                        notesToken.poolAddress(),
                        tokenAddress,
                        Configuration.NOTE_TOKEN_TYPE(notesToken.noteTokenType()) ==
                            Configuration.NOTE_TOKEN_TYPE.SENIOR
                            ? ISecuritizationPool(notesToken.poolAddress()).interestRateSOT()
                            : 0,
                        timestamp
                    );
            }
        }
    }

    function getAssetRiskScoreIdx(
        address poolAddress,
        uint256 overdue
    ) public view returns (bool hasValidRiskScore, uint256 riskScoreIdx) {
        ISecuritizationPool securitizationPool = ISecuritizationPool(poolAddress);
        uint256 riskScoresLength = securitizationPool.getRiskScoresLength();
        for (riskScoreIdx = 0; riskScoreIdx < riskScoresLength; riskScoreIdx++) {
            uint32 daysPastDue = getDaysPastDueByIdx(securitizationPool, riskScoreIdx + 1);
            if (overdue < daysPastDue) return (false, 0);
            else if (riskScoreIdx == riskScoresLength - 1) {
                return (true, riskScoreIdx);
            } else {
                uint32 nextDaysPastDue = getDaysPastDueByIdx(securitizationPool, riskScoreIdx + 1);
                if (overdue < nextDaysPastDue) return (true, riskScoreIdx);
            }
        }
    }

    function getDaysPastDueByIdx(ISecuritizationPool securitizationPool, uint256 idx) private view returns (uint32) {
        (uint32 daysPastDue, , , , , , , , , ) = securitizationPool.riskScores(idx);
        return daysPastDue;
    }

    function getAdvanceRateByIdx(ISecuritizationPool securitizationPool, uint256 idx) private view returns (uint32) {
        (, uint32 advanceRate, , , , , , , , ) = securitizationPool.riskScores(idx);
        return advanceRate;
    }

    function getPenaltyRateByIdx(ISecuritizationPool securitizationPool, uint256 idx) private view returns (uint32) {
        (, , uint32 penaltyRate, , , , , , , ) = securitizationPool.riskScores(idx);
        return penaltyRate;
    }

    function getInterestRateByIdx(ISecuritizationPool securitizationPool, uint256 idx) private view returns (uint32) {
        (, , , uint32 interestRate, , , , , , ) = securitizationPool.riskScores(idx);
        return interestRate;
    }

    function getProbabilityOfDefaultByIdx(
        ISecuritizationPool securitizationPool,
        uint256 idx
    ) private view returns (uint32) {
        (, , , , uint32 probabilityOfDefault, , , , , ) = securitizationPool.riskScores(idx);
        return probabilityOfDefault;
    }

    function getLossGivenDefaultByIdx(
        ISecuritizationPool securitizationPool,
        uint256 idx
    ) private view returns (uint32) {
        (, , , , , uint32 lossGivenDefault, , , , ) = securitizationPool.riskScores(idx);
        return lossGivenDefault;
    }

    function getGracePeriodByIdx(ISecuritizationPool securitizationPool, uint256 idx) private view returns (uint32) {
        (, , , , , , uint32 gracePeriod, , , ) = securitizationPool.riskScores(idx);
        return gracePeriod;
    }

    function getCollectionPeriodByIdx(
        ISecuritizationPool securitizationPool,
        uint256 idx
    ) private view returns (uint32) {
        (, , , , , , , uint32 collectionPeriod, , ) = securitizationPool.riskScores(idx);
        return collectionPeriod;
    }

    function getWriteOffAfterGracePeriodByIdx(
        ISecuritizationPool securitizationPool,
        uint256 idx
    ) private view returns (uint32) {
        (, , , , , , , , uint32 writeOffAfterGracePeriod, ) = securitizationPool.riskScores(idx);
        return writeOffAfterGracePeriod;
    }

    function getWriteOffAfterCollectionPeriodByIdx(
        ISecuritizationPool securitizationPool,
        uint256 idx
    ) private view returns (uint32) {
        (, , , , , , , , , uint32 writeOffAfterCollectionPeriod) = securitizationPool.riskScores(idx);
        return writeOffAfterCollectionPeriod;
    }

    function getRiskScoreByIdx(address pool, uint256 idx) private view returns (RiskScore memory) {
        ISecuritizationPool securitizationPool = ISecuritizationPool(pool);
        return
            RiskScore({
                daysPastDue: getDaysPastDueByIdx(securitizationPool, idx),
                advanceRate: getAdvanceRateByIdx(securitizationPool, idx),
                penaltyRate: getPenaltyRateByIdx(securitizationPool, idx),
                interestRate: getInterestRateByIdx(securitizationPool, idx),
                probabilityOfDefault: getProbabilityOfDefaultByIdx(securitizationPool, idx),
                lossGivenDefault: getLossGivenDefaultByIdx(securitizationPool, idx),
                gracePeriod: getGracePeriodByIdx(securitizationPool, idx),
                collectionPeriod: getCollectionPeriodByIdx(securitizationPool, idx),
                writeOffAfterGracePeriod: getWriteOffAfterGracePeriodByIdx(securitizationPool, idx),
                writeOffAfterCollectionPeriod: getWriteOffAfterCollectionPeriodByIdx(securitizationPool, idx)
            });
    }

    function getOutstandingPrincipalCurrencyByInvestor(address pool, address investor) public view returns (uint256) {
        ISecuritizationPool securitizationPool = ISecuritizationPool(pool);
        ICrowdsale crowdsale = ICrowdsale(securitizationPool.tgeAddress());

        return
            crowdsale.currencyRaisedByInvestor(investor) -
            securitizationPool.paidPrincipalAmountSOTByInvestor(investor);
    }

    function getOutstandingPrincipalCurrencyByInvestors(
        address pool,
        address[] calldata investors
    ) external view returns (uint256) {
        uint256 result = 0;
        for (uint256 i = 0; i < investors.length; i++) {
            result = result + getOutstandingPrincipalCurrencyByInvestor(pool, investors[i]);
        }
        return result;
    }

    function getOutstandingPrincipalCurrency(address pool) external view returns (uint256) {
        ISecuritizationPool securitizationPool = ISecuritizationPool(pool);
        ICrowdsale crowdsale = ICrowdsale(securitizationPool.tgeAddress());

        return crowdsale.currencyRaised() - securitizationPool.paidPrincipalAmountSOT();
    }

    function getPoolValue(address poolAddress)  view public returns (uint256) {
        // ISecuritizationPool securitizationPool = ISecuritizationPool(poolAddress);
        // ICrowdsale crowdsale = ICrowdsale(securitizationPool.tgeAddress());

        // return crowdsale.currencyRaised();
        ISecuritizationPool securitizationPool = ISecuritizationPool(poolAddress);
        address currencyAddress = securitizationPool.underlyingCurrency();
        // currency balance of pool Address
        uint256 balancePool = IERC20(currencyAddress).balanceOf(poolAddress);
        // reserve = currencyRaised - nAVPoolValue;
        // poolValue = reserve + nAVPoolValue;

        return balancePool;
    }

    function getExpectedSeniorAsset(address poolAddress) external view returns (uint256) {
        uint256 expectedSeniorAsset;

        return expectedSeniorAsset;
    }

    function getSeniorDebt(address poolAddress) external view returns (uint256) {
        ISecuritizationPool securitizationPool = ISecuritizationPool(poolAddress);
        
        uint256 seniorInterestRate =  securitizationPool.interestRateSOT();
        
        uint256 seniorDebt;
        seniorDebt = (100 + seniorInterestRate)* seniorDebt;

        return seniorDebt;
    }

    function getSeniorBalance(address poolAddress) external view returns (uint256) {
        uint256 seniorBalance;
        seniorBalance = this.getSeniorAsset(poolAddress) -  this.getSeniorDebt(poolAddress);
        return seniorBalance;
    }

    function getSeniorAsset(address poolAddress) external view returns (uint256) {
        uint256 seniorAsset;
        
        return seniorAsset;
    }
    function getJuniorAsset(address poolAddress)  public returns (uint256) {
        uint256 seniorAsset;
        uint256 poolValue;
        poolValue = this.getPoolValue(poolAddress);
        // uint256 value = poolValue − seniorAsset;
        uint256 juniorAsset = UntangledMath.getMax(1,0);

        return juniorAsset;
    }

    function getNAV(address poolAddress) external view returns (uint256) {
        uint256 currentTimestamp = block.time;
        uint256 nAVPoolValue = this.getExpectedAssetsValue(poolAddress, currentTimestamp);
        return nAVPoolValue;
    }


    // function getMax(uint a, uint b) public pure returns (uint256) {
    //     return a > b ? a : b;
    //     // uint256 i;
    // }

    // function getMin(uint a, uint b) public pure returns (uint256) {
    //     return a < b ? a : b;
    //     // uint256 i;
    // }
}
