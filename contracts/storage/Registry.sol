// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../base/UntangledBase.sol';

contract Registry is UntangledBase {
    mapping(uint8 => address) public contractAddresses;

    event AddressUpdated(address owner, uint8 index, address oldValue, address newValue);

    function initialize() public initializer {
        __UntangledBase__init(_msgSender());
    }

    function _setAddress(uint8 addressIndex, address newAddress) private {
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
        _setAddress(uint8(Configuration.CONTRACT_TYPE.SECURITIZATION_MANAGER), newAddress);
    }

    function setSecuritizationPool(address newAddress) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused nonReentrant {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.SECURITIZATION_POOL), newAddress);
    }

    function setNoteTokenFactory(address newAddress) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused nonReentrant {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.NOTE_TOKEN_FACTORY), newAddress);
    }

    function setTokenGenerationEventFactory(address newAddress)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
        whenNotPaused
        nonReentrant
    {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.TOKEN_GENERATION_EVENT_FACTORY), newAddress);
    }

    function setMintedIncreasingInterestTGE(address newAddress)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
        whenNotPaused
        nonReentrant
    {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.MINTED_INCREASING_INTEREST_TGE), newAddress);
    }

    function setMintedNormalTGE(address newAddress)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
        whenNotPaused
        nonReentrant
    {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.MINTED_NORMAL_TGE), newAddress);
    }

    function setDistributionOperator(address newAddress)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
        whenNotPaused
        nonReentrant
    {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.DISTRIBUTION_OPERATOR), newAddress);
    }

    function setDistributionAssessor(address newAddress)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
        whenNotPaused
        nonReentrant
    {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.DISTRIBUTION_ASSESSOR), newAddress);
    }

    function setLoanAssetToken(address newAddress) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused nonReentrant {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.LOAN_ASSET_TOKEN), newAddress);
    }

    function setAcceptedInvoiceToken(address newAddress)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
        whenNotPaused
        nonReentrant
    {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.ACCEPTED_INVOICE_TOKEN), newAddress);
    }

    function setDistributionTranche(address newAddress) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused nonReentrant {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.DISTRIBUTION_TRANCHE), newAddress);
    }

    function setSecuritizationPoolValueService(address newAddress)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
        whenNotPaused
        nonReentrant
    {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.SECURITIZATION_POOL_VALUE_SERVICE), newAddress);
    }

    function setLoanRegistry(address newAddress) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused nonReentrant {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.LOAN_REGISTRY), newAddress);
    }

    function setLoanInterestTermsContract(address newAddress)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
        whenNotPaused
        nonReentrant
    {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.LOAN_INTEREST_TERMS_CONTRACT), newAddress);
    }

    function setLoanRepaymentRouter(address newAddress) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused nonReentrant {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.LOAN_REPAYMENT_ROUTER), newAddress);
    }

    function setLoanKernel(address newAddress) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused nonReentrant {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.LOAN_KERNEL), newAddress);
    }

    function setCollateralManagementToken(address newAddress) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused nonReentrant {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.COLLATERAL_MANAGEMENT_TOKEN), newAddress);
    }

    function setSupplyChainManagementProgram(address newAddress) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused nonReentrant {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.SUPPLY_CHAIN_MANAGEMENT_PROGRAM), newAddress);
    }

    function setInventoryLoanKernel(address newAddress) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused nonReentrant {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.INVENTORY_LOAN_KERNEL), newAddress);
    }

    function setInventoryLoanRegistry(address newAddress) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused nonReentrant {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.INVENTORY_LOAN_REGISTRY), newAddress);
    }

    function setInventoryLoanRepaymentRouter(address newAddress) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused nonReentrant {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.INVENTORY_LOAN_REPAYMENT_ROUTER), newAddress);
    }

    function setInventoryInterestTermsContract(address newAddress) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused nonReentrant {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.INVENTORY_INTEREST_TERMS_CONTRACT), newAddress);
    }

    function setInventoryCollateralizer(address newAddress) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused nonReentrant {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.INVENTORY_COLLATERALIZER), newAddress);
    }

    function setInvoiceLoanKernel(address newAddress) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused nonReentrant {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.INVOICE_LOAN_KERNEL), newAddress);
    }

    function setInvoiceDebtRegistry(address newAddress) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused nonReentrant {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.INVOICE_DEBT_REGISTRY), newAddress);
    }

    function setInvoiceLoanRepaymentRouter(address newAddress) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused nonReentrant {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.INVOICE_LOAN_REPAYMENT_ROUTER), newAddress);
    }

    function setInvoiceFinanceInterestTermsContract(address newAddress) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused nonReentrant {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.INVOICE_FINANCE_INTEREST_TERMS_CONTRACT), newAddress);
    }

    function setInvoiceCollateralizer(address newAddress) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused nonReentrant {
        _setAddress(uint8(Configuration.CONTRACT_TYPE.INVOICE_COLLATERALIZER), newAddress);
    }
}
