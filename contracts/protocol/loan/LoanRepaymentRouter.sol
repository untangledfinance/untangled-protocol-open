// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol';
import {ISecuritizationPool} from '../pool/ISecuritizationPool.sol';
import {ILoanInterestTermsContract} from '../../interfaces/ILoanInterestTermsContract.sol';
import {ILoanRegistry} from '../../interfaces/ILoanRegistry.sol';

import {UntangledMath} from '../../libraries/UntangledMath.sol';
import {ILoanRepaymentRouter} from './ILoanRepaymentRouter.sol';
import {Registry} from '../../storage/Registry.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {ISecuritizationTGE} from '../pool/ISecuritizationTGE.sol';
import {ISecuritizationPoolStorage} from '../pool/ISecuritizationPoolStorage.sol';

/// @title LoanRepaymentRouter
/// @author Untangled Team
/// @dev Repay for loan
contract LoanRepaymentRouter is ILoanRepaymentRouter {
    using ConfigHelper for Registry;

    function initialize(Registry _registry) public override initializer {
        __UntangledBase__init(_msgSender());
        registry = _registry;
    }

    /// @dev performs various checks to validate the repayment request, including ensuring that the token address is not null,
    /// the amount is greater than zero, and the debt agreement exists
    function _assertRepaymentRequest(bytes32 _agreementId, address _tokenAddress) private returns (bool) {
        require(_tokenAddress != address(0), 'Token address must different with NULL.');

        // Ensure agreement exists.
        if (registry.getLoanAssetToken().ownerOf(uint256(_agreementId)) == address(0)) {
            emit LogError(uint8(Errors.DEBT_AGREEMENT_NONEXISTENT), _agreementId);
            return false;
        }

        return true;
    }

    /// @dev executes the loan repayment by notifying the terms contract about the repayment,
    /// transferring the repayment amount to the creditor, and handling additional logic related to securitization pools
    /// and completed repayments
    function _doRepay(
        bytes32 _agreementId,
        address _payer,
        uint256 _amount,
        address _tokenAddress
    ) private returns (bool) {
        // Notify terms contract

        ILoanRegistry loanRegistry = registry.getLoanRegistry();
        address termsContract = loanRegistry.getTermContract(_agreementId);
        address beneficiary = registry.getLoanAssetToken().ownerOf(uint256(_agreementId));

        uint256 remains = ILoanInterestTermsContract(termsContract).registerRepayment(
            _agreementId,
            _payer,
            beneficiary,
            _amount,
            _tokenAddress
        );

        // Transfer amount to creditor
        if (_payer != address(0x0)) {
            ISecuritizationTGE poolInstance = ISecuritizationTGE(beneficiary);
            if (registry.getSecuritizationManager().isExistingPools(beneficiary))
                beneficiary = ISecuritizationPoolStorage(beneficiary).pot();
            uint256 repayAmount = _amount - remains;
            require(
                IERC20Upgradeable(_tokenAddress).transferFrom(_payer, beneficiary, repayAmount),
                'Unsuccessfully transferred repayment amount to Creditor.'
            );
            poolInstance.increaseTotalAssetRepaidCurrency(repayAmount);
        }
        ILoanInterestTermsContract loanTermContract = registry.getLoanInterestTermsContract();

        if (loanTermContract.completedRepayment(_agreementId)) {
            // Burn LAT token when repay completely
            registry.getLoanKernel().concludeLoan(beneficiary, _agreementId, termsContract);
        }

        // Log event for repayment
        emit LogRepayment(_agreementId, _payer, beneficiary, _amount, _tokenAddress);
        return true;
    }

    /// @inheritdoc ILoanRepaymentRouter
    function repayInBatch(
        bytes32[] calldata agreementIds,
        uint256[] calldata amounts,
        address tokenAddress
    ) external override whenNotPaused nonReentrant returns (bool) {
        uint256 agreementIdsLength = agreementIds.length;
        for (uint256 i = 0; i < agreementIdsLength; i = UntangledMath.uncheckedInc(i)) {
            require(
                _assertRepaymentRequest(agreementIds[i], tokenAddress),
                'LoanRepaymentRouter: Invalid repayment request'
            );
            require(
                _doRepay(agreementIds[i], _msgSender(), amounts[i], tokenAddress),
                'LoanRepaymentRouter: Repayment has failed'
            );
        }
        emit LogRepayments(agreementIds, _msgSender(), amounts);
        return true;
    }

    uint256[50] private __gap;
}
