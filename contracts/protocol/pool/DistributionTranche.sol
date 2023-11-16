// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import './base/SecuritizationPoolServiceBase.sol';
import {IERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol';
import {IDistributionTranche} from './IDistributionTranche.sol';
import {ISecuritizationTGE} from './ISecuritizationTGE.sol';

/// @title DistributionTranche
/// @author Untangled Team
contract DistributionTranche is SecuritizationPoolServiceBase, IDistributionTranche {
    using ConfigHelper for Registry;

    /// @inheritdoc IDistributionTranche
    function redeem(
        address usr,
        address pool,
        address notesToken,
        uint256 currencyAmount,
        uint256 tokenAmount
    ) external whenNotPaused {
        registry.requireDistributionOperator(_msgSender());

        if (tokenAmount > 0) {
            require(
                IERC20Upgradeable(notesToken).transfer(pool, tokenAmount),
                'DistributionTranche: token-transfer-failed'
            );
        }
        ISecuritizationTGE(pool).redeem(usr, notesToken, currencyAmount, tokenAmount);
    }

    /// @inheritdoc IDistributionTranche
    function redeemToken(address noteToken, address usr, uint256 tokenAmount) external whenNotPaused {
        registry.requireDistributionOperator(_msgSender());

        require(
            IERC20Upgradeable(noteToken).transferFrom(usr, address(this), tokenAmount),
            'DistributionTranche: token-transfer-failed'
        );
    }

    uint256[50] private __gap;
}
