// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import './base/SecuritizationPoolServiceBase.sol';

import '@openzeppelin/contracts/interfaces/IERC20.sol';

/// @title DistributionTranche
/// @author Untangled Team
contract DistributionTranche is SecuritizationPoolServiceBase, IDistributionTranche {
    using ConfigHelper for Registry;

    modifier onlyOperator() {
        require(_msgSender() == address(registry.getDistributionOperator()), 'DistributionTranche: Only Operator');
        _;
    }

    /// @inheritdoc IDistributionTranche
    function redeem(
        address usr,
        address pool,
        address notesToken,
        uint256 currencyAmount,
        uint256 tokenAmount
    ) external whenNotPaused nonReentrant onlyOperator {
        if (tokenAmount > 0) {
            require(IERC20(notesToken).transfer(pool, tokenAmount), 'DistributionTranche: token-transfer-failed');
        }
        ISecuritizationPool(pool).redeem(usr, notesToken, currencyAmount, tokenAmount);
    }

    /// @inheritdoc IDistributionTranche
    function redeemToken(address noteToken, address usr, uint256 tokenAmount) external whenNotPaused onlyOperator {
        require(
            IERC20(noteToken).transferFrom(usr, address(this), tokenAmount),
            'DistributionTranche: token-transfer-failed'
        );
    }

    uint256[50] private __gap;
}
