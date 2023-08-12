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
        uint256 ONE_TOKEN = 10 ** uint256(noteToken.decimals());
        if (securitizationPool.sotToken() == address(noteToken)) {
            tokenPrice = registry.getDistributionAssessor().getSOTTokenPrice(
                address(securitizationPool)
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
        } else if (securitizationPool.jotToken() == address(noteToken)) {
            uint256 currencyDecimals = ERC20(securitizationPool.underlyingCurrency()).decimals();
            tokenPrice = registry.getDistributionAssessor().getJOTTokenPrice(
                securitizationPool
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
    ) public whenNotPaused nonReentrant returns (uint256) {
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

    function makeRedeemRequestAndRedeem(address pool, INoteToken noteToken, uint256 tokenAmount) public whenNotPaused nonReentrant returns (uint256) {
        _makeRedeemRequest(noteToken, tokenAmount);
        uint256 currencyLocked = redeem(_msgSender(), pool, address(noteToken));
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
