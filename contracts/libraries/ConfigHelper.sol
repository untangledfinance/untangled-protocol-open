// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../storage/Registry.sol';
import './Configuration.sol';

import '../interfaces/ISecuritizationManager.sol';
import '../interfaces/ISecuritizationPool.sol';
import '../interfaces/INoteTokenFactory.sol';
import '../interfaces/ITokenGenerationEventFactory.sol';
import '../interfaces/IUntangledERC721.sol';
import '../interfaces/IDistributionOperator.sol';
import '../interfaces/IDistributionTranche.sol';
import '../interfaces/ILoanRegistry.sol';
import '../interfaces/ILoanInterestTermsContract.sol';
import '../interfaces/ILoanRepaymentRouter.sol';
import '../interfaces/ILoanKernel.sol';
import '../interfaces/IDistributionAssessor.sol';
import '../interfaces/ISecuritizationPoolValueService.sol';
import '../protocol/note-sale/MintedIncreasingInterestTGE.sol';
import '../protocol/note-sale/MintedNormalTGE.sol';
import '../tokens/ERC1155/CollateralManagementToken.sol';
import '../protocol/cma/SupplyChainManagementProgram.sol';
import '../protocol/loan/inventory/InventoryCollateralizer.sol';
import '../protocol/loan/inventory/InventoryInterestTermsContract.sol';
import '../protocol/loan/inventory/InventoryLoanKernel.sol';
import '../protocol/loan/inventory/InventoryLoanRegistry.sol';
import '../protocol/loan/inventory/InventoryLoanRepaymentRouter.sol';
import '../protocol/loan/invoice/InvoiceCollateralizer.sol';
import '../protocol/loan/invoice/InvoiceDebtRegistry.sol';
import '../protocol/loan/invoice/InvoiceFinanceInterestTermsContract.sol';
import '../protocol/loan/invoice/InvoiceLoanKernel.sol';
import '../protocol/loan/invoice/InvoiceLoanRepaymentRouter.sol';

library ConfigHelper {
    function getAddress(Registry registry, Configuration.CONTRACT_TYPE contractType) internal view returns (address) {
        return registry.getAddress(uint8(contractType));
    }

    function getSecuritizationManager(Registry registry) internal view returns (ISecuritizationManager) {
        return ISecuritizationManager(getAddress(registry, Configuration.CONTRACT_TYPE.SECURITIZATION_MANAGER));
    }

    function getSecuritizationPool(Registry registry) internal view returns (ISecuritizationPool) {
        return ISecuritizationPool(getAddress(registry, Configuration.CONTRACT_TYPE.SECURITIZATION_POOL));
    }

    function getNoteTokenFactory(Registry registry) internal view returns (INoteTokenFactory) {
        return INoteTokenFactory(getAddress(registry, Configuration.CONTRACT_TYPE.NOTE_TOKEN_FACTORY));
    }

    function getTokenGenerationEventFactory(Registry registry) internal view returns (ITokenGenerationEventFactory) {
        return
            ITokenGenerationEventFactory(
                getAddress(registry, Configuration.CONTRACT_TYPE.TOKEN_GENERATION_EVENT_FACTORY)
            );
    }

    function getDistributionOperator(Registry registry) internal view returns (IDistributionOperator) {
        return IDistributionOperator(getAddress(registry, Configuration.CONTRACT_TYPE.DISTRIBUTION_OPERATOR));
    }

    function getLoanAssetToken(Registry registry) internal view returns (IUntangledERC721) {
        return IUntangledERC721(getAddress(registry, Configuration.CONTRACT_TYPE.LOAN_ASSET_TOKEN));
    }

    function getAcceptedInvoiceToken(Registry registry) internal view returns (AcceptedInvoiceToken) {
        return AcceptedInvoiceToken(getAddress(registry, Configuration.CONTRACT_TYPE.ACCEPTED_INVOICE_TOKEN));
    }

    function getLoanRegistry(Registry registry) internal view returns (ILoanRegistry) {
        return ILoanRegistry(getAddress(registry, Configuration.CONTRACT_TYPE.LOAN_REGISTRY));
    }

    function getLoanInterestTermsContract(Registry registry) internal view returns (ILoanInterestTermsContract) {
        return
            ILoanInterestTermsContract(getAddress(registry, Configuration.CONTRACT_TYPE.LOAN_INTEREST_TERMS_CONTRACT));
    }

    function getLoanRepaymentRouter(Registry registry) internal view returns (ILoanRepaymentRouter) {
        return ILoanRepaymentRouter(getAddress(registry, Configuration.CONTRACT_TYPE.LOAN_REPAYMENT_ROUTER));
    }

    function getLoanKernel(Registry registry) internal view returns (ILoanKernel) {
        return ILoanKernel(getAddress(registry, Configuration.CONTRACT_TYPE.LOAN_KERNEL));
    }

    function getDistributionTranche(Registry registry) internal view returns (IDistributionTranche) {
        return IDistributionTranche(getAddress(registry, Configuration.CONTRACT_TYPE.DISTRIBUTION_TRANCHE));
    }

    function getSecuritizationPoolValueService(Registry registry)
        internal
        view
        returns (ISecuritizationPoolValueService)
    {
        return
            ISecuritizationPoolValueService(
                getAddress(registry, Configuration.CONTRACT_TYPE.SECURITIZATION_POOL_VALUE_SERVICE)
            );
    }

    function getDistributionAssessor(Registry registry) internal view returns (IDistributionAssessor) {
        return IDistributionAssessor(getAddress(registry, Configuration.CONTRACT_TYPE.DISTRIBUTION_ASSESSOR));
    }

    function getMintedIncreasingInterestTGE(Registry registry) internal view returns (MintedIncreasingInterestTGE) {
        return
            MintedIncreasingInterestTGE(
                getAddress(registry, Configuration.CONTRACT_TYPE.MINTED_INCREASING_INTEREST_TGE)
            );
    }

    function getMintedNormalTGE(Registry registry) internal view returns (MintedNormalTGE) {
        return
        MintedNormalTGE(
            getAddress(registry, Configuration.CONTRACT_TYPE.MINTED_NORMAL_TGE)
        );
    }

    function getCollateralManagementToken(Registry registry) internal view returns (CollateralManagementToken) {
        return CollateralManagementToken(getAddress(registry, Configuration.CONTRACT_TYPE.COLLATERAL_MANAGEMENT_TOKEN));
    }

    function getSupplyChainManagementProgram(Registry registry) internal view returns (SupplyChainManagementProgram) {
        return SupplyChainManagementProgram(getAddress(registry, Configuration.CONTRACT_TYPE.SUPPLY_CHAIN_MANAGEMENT_PROGRAM));
    }

    function getInventoryLoanRegistry(Registry registry) internal view returns (InventoryLoanRegistry) {
        return InventoryLoanRegistry(getAddress(registry, Configuration.CONTRACT_TYPE.INVENTORY_LOAN_REGISTRY));
    }

    function getInventoryCollateralizer(Registry registry) internal view returns (InventoryCollateralizer) {
        return InventoryCollateralizer(getAddress(registry, Configuration.CONTRACT_TYPE.INVENTORY_COLLATERALIZER));
    }

    function getInventoryInterestTermsContract(Registry registry) internal view returns (InventoryInterestTermsContract) {
        return InventoryInterestTermsContract(getAddress(registry, Configuration.CONTRACT_TYPE.INVENTORY_INTEREST_TERMS_CONTRACT));
    }

    function getInventoryLoanKernel(Registry registry) internal view returns (InventoryLoanKernel) {
        return InventoryLoanKernel(getAddress(registry, Configuration.CONTRACT_TYPE.INVENTORY_LOAN_KERNEL));
    }

    function getInventoryLoanRepaymentRouter(Registry registry) internal view returns (InventoryLoanRepaymentRouter) {
        return InventoryLoanRepaymentRouter(getAddress(registry, Configuration.CONTRACT_TYPE.INVENTORY_LOAN_REPAYMENT_ROUTER));
    }

    function getInvoiceDebtRegistry(Registry registry) internal view returns (InvoiceDebtRegistry) {
        return InvoiceDebtRegistry(getAddress(registry, Configuration.CONTRACT_TYPE.INVOICE_DEBT_REGISTRY));
    }

    function getInvoiceCollateralizer(Registry registry) internal view returns (InvoiceCollateralizer) {
        return InvoiceCollateralizer(getAddress(registry, Configuration.CONTRACT_TYPE.INVOICE_COLLATERALIZER));
    }

    function getInvoiceFinanceInterestTermsContract(Registry registry) internal view returns (InvoiceFinanceInterestTermsContract) {
        return InvoiceFinanceInterestTermsContract(getAddress(registry, Configuration.CONTRACT_TYPE.INVOICE_FINANCE_INTEREST_TERMS_CONTRACT));
    }

    function getInvoiceLoanKernel(Registry registry) internal view returns (InvoiceLoanKernel) {
        return InvoiceLoanKernel(getAddress(registry, Configuration.CONTRACT_TYPE.INVOICE_LOAN_KERNEL));
    }

    function getInvoiceLoanRepaymentRouter(Registry registry) internal view returns (InvoiceLoanRepaymentRouter) {
        return InvoiceLoanRepaymentRouter(getAddress(registry, Configuration.CONTRACT_TYPE.INVOICE_LOAN_REPAYMENT_ROUTER));
    }
}
