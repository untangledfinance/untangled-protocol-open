// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './base/SecuritizationPoolServiceBase.sol';

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract DistributionTranche is SecuritizationPoolServiceBase, IDistributionTranche {
    using ConfigHelper for Registry;

    modifier onlyOperator() {
        require(_msgSender() == address(registry.getDistributionOperator()), 'DistributionTranche: Only Operator');
        _;
    }

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

    function redeemToken(
        address noteToken,
        address usr,
        uint256 tokenAmount
    ) external whenNotPaused nonReentrant onlyOperator returns (bool) {
        return IERC20(noteToken).transferFrom(usr, address(this), tokenAmount);
    }
}
