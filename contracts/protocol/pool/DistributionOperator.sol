// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/interfaces/IERC20.sol';
import './base/SecuritizationPoolServiceBase.sol';
import '../../interfaces/INoteToken.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';

/// @title DistributionOperator
/// @author Untangled Team
contract DistributionOperator is SecuritizationPoolServiceBase, IDistributionOperator {
    using ConfigHelper for Registry;

    enum SettlementType {
        FEE,
        REDEEM,
        PRINCIPAL_REDEEM,
        INTEREST_REDEEM
    }

    struct DistributePercent {
        address investor;
        uint256 currencyDistribute;
        uint256 tokenBurn;
        uint256 paidInterestAmount;
    }

    event TokensRedeemed(
        address indexed redeemer,
        address indexed tokenAddress,
        uint256 currencyAmount,
        uint256 tokenAmount
    );

    /// @dev Create a redemption request for note token
    /// @param noteToken SOT/JOT token address
    /// @param tokenAmount Amount of SOT/JOT token to be redeemed
    function _makeRedeemRequest(INoteToken noteToken, uint256 tokenAmount) internal {
        ISecuritizationPool securitizationPool = ISecuritizationPool(noteToken.poolAddress());
        require(
            registry.getNoteTokenFactory().isExistingTokens(address(noteToken)),
            'DistributionOperator: Invalid NoteToken'
        );

        require(noteToken.balanceOf(_msgSender()) >= tokenAmount, 'DistributionOperator: Invalid token amount');

        IDistributionTranche tranche = registry.getDistributionTranche();
        require(
            noteToken.allowance(_msgSender(), address(tranche)) >= tokenAmount,
            'DistributionOperator: Invalid token allowance'
        );

        uint256 tokenPrice;
        uint256 tokenToBeRedeemed;
        uint256 currencyAmtToBeDistributed;
        if (securitizationPool.sotToken() == address(noteToken)) {
            tokenPrice = registry.getDistributionAssessor().getSOTTokenPrice(address(securitizationPool));

            tokenToBeRedeemed = Math.min(
                IERC20(securitizationPool.underlyingCurrency()).balanceOf(securitizationPool.pot()) / tokenPrice,
                tokenAmount
            );
            currencyAmtToBeDistributed = tokenToBeRedeemed * tokenPrice;

            securitizationPool.increaseLockedDistributeBalance(
                address(noteToken),
                _msgSender(),
                currencyAmtToBeDistributed,
                tokenToBeRedeemed
            );

            tranche.redeemToken(address(noteToken), _msgSender(), tokenToBeRedeemed);
        } else if (securitizationPool.jotToken() == address(noteToken)) {
            tokenPrice = registry.getDistributionAssessor().getJOTTokenPrice(securitizationPool);

            tokenToBeRedeemed = Math.min(
                IERC20(securitizationPool.underlyingCurrency()).balanceOf(securitizationPool.pot()) / tokenPrice,
                tokenAmount
            );

            currencyAmtToBeDistributed = tokenToBeRedeemed * tokenPrice;

            securitizationPool.increaseLockedDistributeBalance(
                address(noteToken),
                _msgSender(),
                currencyAmtToBeDistributed,
                tokenToBeRedeemed
            );

            tranche.redeemToken(address(noteToken), _msgSender(), tokenToBeRedeemed);
        }
    }

    /// @notice Redeem SOT/JOT token and receive an amount of currency
    /// @dev Fulfill redeem request created
    /// @param redeemer Redeemer wallet address
    /// @param pool Pool address which issued note token
    /// @param tokenAddress Note token address
    function _redeem(
        address redeemer,
        address pool,
        address tokenAddress
    ) private whenNotPaused returns (uint256) {
        ISecuritizationPool securitizationPool = ISecuritizationPool(pool);

        uint256 currencyLocked = securitizationPool.lockedDistributeBalances(tokenAddress, redeemer);
        uint256 tokenRedeem = securitizationPool.lockedRedeemBalances(tokenAddress, redeemer);
        if (currencyLocked > 0) {
            _redeem(
                redeemer,
                pool,
                tokenAddress,
                tokenRedeem,
                currencyLocked,
                registry.getDistributionTranche(),
                securitizationPool
            );
        }

        emit TokensRedeemed(redeemer, tokenAddress, currencyLocked, tokenRedeem);

        return currencyLocked;
    }

    /// @dev This calls make redeem request and redeem at once
    function makeRedeemRequestAndRedeem(
        address pool,
        INoteToken noteToken,
        uint256 tokenAmount
    ) public whenNotPaused nonReentrant returns (uint256) {
        _makeRedeemRequest(noteToken, tokenAmount);
        uint256 currencyLocked = _redeem(_msgSender(), pool, address(noteToken));
        return currencyLocked;
    }

    function makeRedeemRequestAndRedeemBatch(
        address[] calldata pools,
        INoteToken[] calldata noteTokens,
        uint256[] calldata tokenAmounts
    ) public whenNotPaused nonReentrant {
        address redeemer = _msgSender();
        uint256 poolsLength = pools.length;
        for (uint256 i = 0; i < poolsLength; i = UntangledMath.uncheckedInc(i)) {
            _makeRedeemRequest(noteTokens[i], tokenAmounts[i]);
            _redeem(redeemer, pools[i], address(noteTokens[i]));
        }
    }

    function _redeem(
        address redeemer,
        address pool,
        address tokenAddress,
        uint256 tokenAmount,
        uint256 currencyAmount,
        IDistributionTranche tranche,
        ISecuritizationPool securitizationPool
    ) internal {
        securitizationPool.decreaseLockedDistributeBalance(tokenAddress, redeemer, currencyAmount, tokenAmount);

        tranche.redeem(redeemer, pool, tokenAddress, currencyAmount, tokenAmount);
    }
}
