// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '../storage/Registry.sol';
import './Configuration.sol';

import '../protocol/pool/ISecuritizationManager.sol';
import '../protocol/pool/ISecuritizationPool.sol';
import '../interfaces/INoteTokenFactory.sol';
import '../interfaces/ITokenGenerationEventFactory.sol';
import '../interfaces/IUntangledERC721.sol';
import '../interfaces/IDistributionOperator.sol';
import '../interfaces/IDistributionTranche.sol';
import '../interfaces/ILoanRegistry.sol';
import '../interfaces/ILoanInterestTermsContract.sol';
import '../interfaces/ILoanRepaymentRouter.sol';
import '../interfaces/ILoanKernel.sol';
import {IDistributionAssessor} from '../interfaces/IDistributionAssessor.sol';
import '../interfaces/ISecuritizationPoolValueService.sol';

import {MintedIncreasingInterestTGE} from '../protocol/note-sale/MintedIncreasingInterestTGE.sol';
import {MintedNormalTGE} from '../protocol/note-sale/MintedNormalTGE.sol';
import {AcceptedInvoiceToken} from '../tokens/ERC721/invoice/AcceptedInvoiceToken.sol';
import '../interfaces/IGo.sol';

/**
 * @title ConfigHelper
 * @notice A convenience library for getting easy access to other contracts and constants within the
 *  protocol, through the use of the Registry contract
 * @author Untangled Team
 */
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

    function getNoteToken(Registry registry) internal view returns (INoteToken) {
        return INoteToken(getAddress(registry, Configuration.CONTRACT_TYPE.NOTE_TOKEN));
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

    function getSecuritizationPoolValueService(
        Registry registry
    ) internal view returns (ISecuritizationPoolValueService) {
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
        return MintedNormalTGE(getAddress(registry, Configuration.CONTRACT_TYPE.MINTED_NORMAL_TGE));
    }

    function getGo(Registry registry) internal view returns (IGo) {
        return IGo(getAddress(registry, Configuration.CONTRACT_TYPE.GO));
    }
}
