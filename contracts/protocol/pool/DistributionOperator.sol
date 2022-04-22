// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/interfaces/IERC20.sol';
import './base/SecuritizationPoolServiceBase.sol';
import '../../interfaces/INoteToken.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';

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

    function makeRedeemRequest(INoteToken noteToken, uint256 tokenAmount) external whenNotPaused nonReentrant {
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
        uint256 ONE_TOKEN = 10**uint256(noteToken.decimals());
        if (securitizationPool.sotToken() == address(noteToken)) {
            tokenPrice = registry.getDistributionAssessor().getSOTTokenPrice(
                address(securitizationPool),
                block.timestamp
            );

            tokenToBeRedeemed = Math.min(
                (IERC20(securitizationPool.underlyingCurrency()).balanceOf(securitizationPool.pot()) * ONE_TOKEN) /
                    tokenPrice,
                tokenAmount
            );
            currencyAmtToBeDistributed = (tokenToBeRedeemed * tokenPrice) / ONE_TOKEN;

            securitizationPool.increaseLockedDistributeBalance(
                address(noteToken),
                _msgSender(),
                currencyAmtToBeDistributed,
                tokenToBeRedeemed
            );

            tranche.redeemToken(address(noteToken), _msgSender(), tokenToBeRedeemed);
        }
    }

    function _distributeJOTInBatch(
        ISecuritizationPool securitizationPool,
        uint256 distributeAmount,
        uint256 totalSupply,
        address[] memory jotInvestors
    ) internal returns (uint256 _remainingAmt) {
        _remainingAmt = distributeAmount;
        address jotToken = securitizationPool.jotToken();

        uint256 tokenPrice = registry.getDistributionAssessor().calcTokenPrice(address(securitizationPool), jotToken);
        for (uint256 i = 0; i < jotInvestors.length; i++) {
            _distributeJOT(securitizationPool, jotToken, jotInvestors[i], tokenPrice, distributeAmount, totalSupply);
        }
    }

    function _distributeJOT(
        ISecuritizationPool securitizationPool,
        address tokenAddress,
        address investor,
        uint256 tokenPrice,
        uint256 currencyDistribute,
        uint256 totalSupply
    ) internal {
        require(tokenPrice > 0, 'DistributionOperator: tranche is bankrupt');
        uint256 distributeAmount = _calculateAmountDistribute(
            investor,
            tokenAddress,
            currencyDistribute,
            totalSupply,
            securitizationPool
        );

        uint256 tokenAmount = convertCurrencyAmountToTokenValue(
            address(securitizationPool),
            tokenAddress,
            (distributeAmount * Configuration.PRICE_SCALING_FACTOR) / tokenPrice
        );
        securitizationPool.increaseLockedDistributeBalance(tokenAddress, investor, distributeAmount, tokenAmount);
    }

    function redeemBatch(
        address[] calldata redeemers,
        address pool,
        address tokenAddress
    ) external whenNotPaused nonReentrant {
        ISecuritizationPool securitizationPool = ISecuritizationPool(pool);

        for (uint256 i = 0; i < redeemers.length; ++i) {
            uint256 currencyLocked = securitizationPool.lockedDistributeBalances(tokenAddress, redeemers[i]);
            uint256 tokenRedeem = securitizationPool.lockedRedeemBalances(tokenAddress, redeemers[i]);
            if (currencyLocked > 0) {
                _redeem(
                    redeemers[i],
                    pool,
                    tokenAddress,
                    tokenRedeem,
                    currencyLocked,
                    registry.getDistributionTranche(),
                    securitizationPool
                );
            }
        }
    }

    function redeem(
        address redeemer,
        address pool,
        address tokenAddress
    ) external whenNotPaused nonReentrant returns (uint256) {
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

    function _calculateAmountDistribute(
        address investor,
        address tokenAddress,
        uint256 totalCurrencyToDistribute,
        uint256 totalSupply,
        ISecuritizationPool securitizationPool
    ) internal view returns (uint256) {
        uint256 currentToken = IERC20(tokenAddress).balanceOf(investor);

        uint256 tokenRedeem = securitizationPool.lockedRedeemBalances(tokenAddress, investor);

        return ((currentToken - tokenRedeem) * totalCurrencyToDistribute) / totalSupply;
    }
}
