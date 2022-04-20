// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../base/UntangledBase.sol';

contract Registry is UntangledBase {
    mapping(uint8 => address) public contractAddresses;

    event AddressUpdated(address owner, uint8 index, address oldValue, address newValue);

    function initialize() public initializer {
        __UntangledBase__init(address(this));
    }

    function setAddress(uint8 addressIndex, address newAddress) private {
        emit AddressUpdated(_msgSender(), addressIndex, contractAddresses[addressIndex], newAddress);
        contractAddresses[addressIndex] = newAddress;
    }

    function getAddress(uint8 index) public view returns (address) {
        return contractAddresses[index];
    }

    function setSecuritizationManager(address newAddress)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
        whenNotPaused
        nonReentrant
    {
        setAddress(uint8(Configuration.CONTRACT_TYPE.SECURITIZATION_MANAGER), newAddress);
    }

    function setSecuritizationPool(address newAddress) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused nonReentrant {
        setAddress(uint8(Configuration.CONTRACT_TYPE.SECURITIZATION_POOL), newAddress);
    }

    function setNoteTokenFactory(address newAddress) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused nonReentrant {
        setAddress(uint8(Configuration.CONTRACT_TYPE.NOTE_TOKEN_FACTORY), newAddress);
    }

    function setTokenGenerationEventFactory(address newAddress)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
        whenNotPaused
        nonReentrant
    {
        setAddress(uint8(Configuration.CONTRACT_TYPE.TOKEN_GENERATION_EVENT_FACTORY), newAddress);
    }

    function setDistributionOperator(address newAddress)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
        whenNotPaused
        nonReentrant
    {
        setAddress(uint8(Configuration.CONTRACT_TYPE.DISTRIBUTION_OPERATOR), newAddress);
    }

    function setLoanAssetToken(address newAddress) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused nonReentrant {
        setAddress(uint8(Configuration.CONTRACT_TYPE.LOAN_ASSET_TOKEN), newAddress);
    }

    function setAcceptedInvoiceToken(address newAddress)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
        whenNotPaused
        nonReentrant
    {
        setAddress(uint8(Configuration.CONTRACT_TYPE.ACCEPTED_INVOICE_TOKEN), newAddress);
    }

    function setDistributionTranche(address newAddress) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused nonReentrant {
        setAddress(uint8(Configuration.CONTRACT_TYPE.DISTRIBUTION_TRANCHE), newAddress);
    }
}
