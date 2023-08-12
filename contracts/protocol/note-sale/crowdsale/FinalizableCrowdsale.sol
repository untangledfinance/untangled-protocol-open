// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './TimedCrowdsale.sol';

abstract contract FinalizableCrowdsale is TimedCrowdsale {
    bool public finalized;

    event CrowdsaleFinalized();

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

    function _finalization() internal virtual {
        // solhint-disable-previous-line no-empty-blocks
    }
}
