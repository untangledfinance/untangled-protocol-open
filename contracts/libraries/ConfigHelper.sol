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
import '../interfaces/IExternalLoanDebtRegistry.sol';
import '../interfaces/IExternalLoanInterestTermsContract.sol';
import '../interfaces/IExternalLoanRepaymentRouter.sol';
import '../interfaces/IERC20TokenRegistry.sol';
import '../interfaces/ITokenTransferProxy.sol';

contract PoolManagementLike {
    mapping(address => bool) public isExistingPools;
}

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

    function getAcceptedInvoiceToken(Registry registry) internal view returns (IUntangledERC721) {
        return IUntangledERC721(getAddress(registry, Configuration.CONTRACT_TYPE.ACCEPTED_INVOICE_TOKEN));
    }

    function getExternalLoanDebtRegistry(Registry registry) internal view returns (IExternalLoanDebtRegistry) {
        return IExternalLoanDebtRegistry(getAddress(registry, Configuration.CONTRACT_TYPE.EXTERNAL_LOAN_DEBT_REGISTRY));
    }

    function getExternalLoanInterestTermsContract(Registry registry) internal view returns (IExternalLoanInterestTermsContract) {
        return IExternalLoanInterestTermsContract(getAddress(registry, Configuration.CONTRACT_TYPE.EXTERNAL_LOAN_INTEREST_TERMS_CONTRACT));
    }

    function getExternalLoanRepaymentRouter(Registry registry) internal view returns (IExternalLoanRepaymentRouter) {
        return IExternalLoanRepaymentRouter(getAddress(registry, Configuration.CONTRACT_TYPE.EXTERNAL_LOAN_REPAYMENT_ROUTER));
    }

    function getERC20TokenRegistry(Registry registry) internal view returns (IERC20TokenRegistry) {
        return IERC20TokenRegistry(getAddress(registry, Configuration.CONTRACT_TYPE.ERC20_TOKEN_REGISTRY));
    }

    function getERC20TokenTransferProxy(Registry registry) internal view returns (ITokenTransferProxy) {
        return ITokenTransferProxy(getAddress(registry, Configuration.CONTRACT_TYPE.ERC20_TOKEN_TRANSFER_PROXY));
    }

    function getPoolManagementLike(Registry registry) internal view returns (PoolManagementLike) {
        return PoolManagementLike(getAddress(registry, Configuration.CONTRACT_TYPE.SECURITIZATION_MANAGEMENT_PROJECT));
    }

    function getDistributionTranche(Registry registry) internal view returns (IDistributionTranche) {
        return IDistributionTranche(getAddress(registry, Configuration.CONTRACT_TYPE.DISTRIBUTION_TRANCHE));
    }
}
