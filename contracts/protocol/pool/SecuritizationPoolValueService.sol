// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol';
import {IERC20MetadataUpgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC20MetadataUpgradeable.sol';

import {INoteToken} from '../../interfaces/INoteToken.sol';
import {IUntangledERC721} from '../../interfaces/IUntangledERC721.sol';
import {ICrowdSale} from '../../interfaces/ICrowdSale.sol';
import {ILoanRegistry} from '../../interfaces/ILoanRegistry.sol';

import {ISecuritizationPool} from './ISecuritizationPool.sol';
import {ISecuritizationPoolValueService} from './ISecuritizationPoolValueService.sol';
import {IDistributionAssessor} from './IDistributionAssessor.sol';

import {NAVCalculation} from './base/NAVCalculation.sol';
import {SecuritizationPoolServiceBase} from './base/SecuritizationPoolServiceBase.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {Registry} from '../../storage/Registry.sol';
import {Configuration} from '../../libraries/Configuration.sol';
import {UntangledMath} from '../../libraries/UntangledMath.sol';
import {IPoolNAV} from './IPoolNAV.sol';
import {ISecuritizationPoolStorage} from './ISecuritizationPoolStorage.sol';

import {ISecuritizationTGE} from './ISecuritizationTGE.sol';

import {RiskScore} from './base/types.sol';

/// @title SecuritizationPoolValueService
/// @author Untangled Team
/// @dev Calculate pool's values
contract SecuritizationPoolValueService is
    SecuritizationPoolServiceBase,
    NAVCalculation,
    ISecuritizationPoolValueService
{
    using ConfigHelper for Registry;

    uint256 public constant RATE_SCALING_FACTOR = 10 ** 4;

    function getExpectedLATAssetValue(address poolAddress) public view returns (uint256) {
        return IPoolNAV(ISecuritizationPoolStorage(poolAddress).poolNAV()).currentNAV();
    }

    function getExpectedAssetValue(address poolAddress, bytes32 tokenId) public view returns (uint256) {
        IPoolNAV poolNav = IPoolNAV(ISecuritizationPoolStorage(poolAddress).poolNAV());
        return poolNav.currentNAVAsset(tokenId);
    }

    function getExpectedAssetValues(
        address poolAddress,
        bytes32[] calldata tokenIds
    ) public view returns (uint256[] memory expectedAssetsValues) {
        expectedAssetsValues = new uint256[](tokenIds.length);
        IPoolNAV poolNav = IPoolNAV(ISecuritizationPoolStorage(poolAddress).poolNAV());
        for (uint i = 0; i < tokenIds.length; i++) {
            expectedAssetsValues[i] = poolNav.currentNAVAsset(tokenIds[i]);
        }

        return expectedAssetsValues;
    }

    function getDebtAssetValues(
        address poolAddress,
        bytes32[] calldata tokenIds
    ) public view returns (uint256[] memory debtAssetsValues) {
        debtAssetsValues = new uint256[](tokenIds.length);
        IPoolNAV poolNav = IPoolNAV(ISecuritizationPoolStorage(poolAddress).poolNAV());
        for (uint i = 0; i < tokenIds.length; i++) {
            debtAssetsValues[i] = poolNav.debt(uint256(tokenIds[i]));
        }

        return debtAssetsValues;
    }

    /// @inheritdoc ISecuritizationPoolValueService
    function getExpectedAssetsValue(address poolAddress) external view returns (uint256 expectedAssetsValue) {
        expectedAssetsValue = 0;
        ISecuritizationPool securitizationPool = ISecuritizationPool(poolAddress);

        expectedAssetsValue =
            expectedAssetsValue +
            IPoolNAV(ISecuritizationPoolStorage(poolAddress).poolNAV()).currentNAV();

        uint256 tokenAssetAddressesLength = securitizationPool.getTokenAssetAddressesLength();
        for (uint256 i = 0; i < tokenAssetAddressesLength; i = UntangledMath.uncheckedInc(i)) {
            address tokenAddress = securitizationPool.tokenAssetAddresses(i);
            INoteToken notesToken = INoteToken(tokenAddress);
            if (notesToken.balanceOf(poolAddress) > 0) {
                expectedAssetsValue =
                    expectedAssetsValue +
                    registry.getDistributionAssessor().calcCorrespondingTotalAssetValue(tokenAddress, poolAddress);
            }
        }
    }

    function getPoolValue(address poolAddress) external view returns (uint256) {
        ISecuritizationPool securitizationPool = ISecuritizationPool(poolAddress);
        require(address(securitizationPool) != address(0), 'Pool was not deployed');
        uint256 nAVpoolValue = this.getExpectedLATAssetValue(poolAddress);

        // use reserve variable instead
        uint256 balancePool = ISecuritizationTGE(poolAddress).reserve();
        uint256 poolValue = balancePool + nAVpoolValue;

        return poolValue;
    }

    // @notice this function return value 90 in example
    function getBeginningSeniorAsset(address poolAddress) external view returns (uint256) {
        require(poolAddress != address(0), 'Invalid pool address');
        ISecuritizationTGE securitizationPool = ISecuritizationTGE(poolAddress);
        address sotToken = securitizationPool.sotToken();
        require(sotToken != address(0), 'Invalid sot address');
        uint256 tokenSupply = INoteToken(sotToken).totalSupply();
        return tokenSupply;
    }

    // @notice this function will return 72 in example
    function getBeginningSeniorDebt(address poolAddress) external view returns (uint256) {
        uint256 poolValue = this.getPoolValue(poolAddress);
        if (poolValue == 0) return 0;

        uint256 beginningSeniorAsset = this.getBeginningSeniorAsset(poolAddress);

        return beginningSeniorAsset;
    }

    // @notice get beginning of senior debt, get interest of this debt over number of interval
    function getSeniorDebt(address poolAddress) external view returns (uint256) {
        uint256 beginningSeniorDebt = this.getBeginningSeniorDebt(poolAddress);
        if (beginningSeniorDebt == 0) return 0;
        ISecuritizationPoolStorage securitizationPool = ISecuritizationPoolStorage(poolAddress);
        require(address(securitizationPool) != address(0), 'Pool was not deployed');
        uint256 seniorInterestRate = ISecuritizationTGE(poolAddress).interestRateSOT();
        uint256 openingTime = securitizationPool.openingBlockTimestamp();
        uint256 compoundingPeriods = block.timestamp - openingTime;
        uint256 oneYearInSeconds = NAVCalculation.YEAR_LENGTH_IN_SECONDS;

        uint256 seniorDebt = beginningSeniorDebt +
            (beginningSeniorDebt * seniorInterestRate * compoundingPeriods) /
            (RATE_SCALING_FACTOR * oneYearInSeconds);
        return seniorDebt;
    }

    // @notice get beginning senior asset, then calculate ratio reserve on pools.Finaly multiple them
    function getSeniorBalance(address poolAddress) external view returns (uint256) {
        return this.getBeginningSeniorAsset(poolAddress) - this.getBeginningSeniorDebt(poolAddress);
    }

    /// @inheritdoc ISecuritizationPoolValueService
    function getSeniorAsset(address poolAddress) external view returns (uint256) {
        // we need to change this value with interest rate by time
        uint256 seniorAsset;
        uint256 poolValue = this.getPoolValue(poolAddress);
        uint256 expectedSeniorAsset = this.getExpectedSeniorAssets(poolAddress);

        if (poolValue > expectedSeniorAsset) {
            seniorAsset = expectedSeniorAsset;
        } else {
            // case of default
            seniorAsset = poolValue;
        }

        return seniorAsset;
    }

    /// @inheritdoc ISecuritizationPoolValueService
    function getJuniorAsset(address poolAddress) external view returns (uint256) {
        uint256 poolValue = this.getPoolValue(poolAddress);
        uint256 seniorAsset = this.getSeniorAsset(poolAddress);
        uint256 juniorAsset = 0;
        if (poolValue >= seniorAsset) {
            juniorAsset = poolValue - seniorAsset;
        }

        return juniorAsset;
    }

    /// @inheritdoc ISecuritizationPoolValueService
    function getJuniorRatio(address poolAddress) external view returns (uint256) {
        uint256 rateSenior = this.getSeniorRatio(poolAddress);
        require(rateSenior <= 100 * RATE_SCALING_FACTOR, 'securitizationPool.rateSenior >100');

        return 100 * RATE_SCALING_FACTOR - rateSenior;
    }

    function getSeniorRatio(address poolAddress) external view returns (uint256) {
        uint256 seniorAsset = this.getSeniorAsset(poolAddress);
        uint256 poolValue = this.getPoolValue(poolAddress);
        if (poolValue == 0) {
            return 0;
        }

        return (seniorAsset * 100 * RATE_SCALING_FACTOR) / poolValue;
    }

    function getExpectedSeniorAssets(address poolAddress) external view returns (uint256) {
        uint256 senorDebt = this.getSeniorDebt(poolAddress);
        uint256 seniorBalance = this.getSeniorBalance(poolAddress);
        return senorDebt + seniorBalance;
    }

    uint256[50] private __gap;
}
