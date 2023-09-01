// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import './TimedCrowdsale.sol';

abstract contract FinalizableCrowdsale is TimedCrowdsale {
    bool public finalized;

    event CrowdsaleFinalized();

    /// @dev Validates that the crowdsale has not already been finalized and that it has either closed or reached the total cap
    function finalize(bool claimRemainToken, address remainTokenRecipient)
        public
        whenNotPaused
        nonReentrant
        onlyRole(OWNER_ROLE)
    {
        require(!finalized, 'FinalizableCrowdsale: already finalized');
        require(hasClosed() || totalCapReached(), 'FinalizableCrowdsale: not closed');

        if (!isDistributedFully() && !isLongSale()) {
            uint256 tokenRemain = 0;
            tokenRemain = _getTokenAmount(getCurrencyRemainAmount());

            if (claimRemainToken) {
                _processPurchase(remainTokenRecipient, tokenRemain);
            } else {
                _ejectTokens(tokenRemain);
            }
        }

        finalized = true;

        _finalization();
        emit CrowdsaleFinalized();
    }

    /// @dev This function is meant to be overridden in derived contracts to implement specific finalization logic
    function _finalization() internal virtual {
        // solhint-disable-previous-line no-empty-blocks
    }
}
