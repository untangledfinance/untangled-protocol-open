// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Configuration {
    // NEVER EVER CHANGE THE ORDER OF THESE!
    // You can rename or append. But NEVER change the order.
    enum CONTRACT_TYPE {
        SECURITIZATION_MANAGER,
        SECURITIZATION_POOL,
        NOTE_TOKEN_FACTORY,
        TOKEN_GENERATION_EVENT_FACTORY,
        DISTRIBUTION_OPERATOR,
        DISTRIBUTION_TRANCHE,
        LOAN_ASSET_TOKEN,
        ACCEPTED_INVOICE_TOKEN
    }

    enum NOTE_TOKEN_TYPE {
        SENIOR,
        JUNIOR
    }
}
