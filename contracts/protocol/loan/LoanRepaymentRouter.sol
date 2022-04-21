// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/interfaces/IERC20.sol';
import '../../interfaces/ILoanInterestTermsContract.sol';
import '../../interfaces/ISecuritizationPool.sol';
import '../../interfaces/ILoanRegistry.sol';
import '../../interfaces/ILoanRepaymentRouter.sol';
import '../../libraries/ConfigHelper.sol';

/**
 * Repayment Router smart contract for Loan
 */
contract LoanRepaymentRouter is ILoanRepaymentRouter {
    using ConfigHelper for Registry;

    function initialize(Registry _registry) public override initializer {
        __UntangledBase__init(_msgSender());
        registry = _registry;
    }

    function _assertRepaymentRequest(
        bytes32 _agreementId,
        address _payer,
        uint256 _amount,
        address _tokenAddress
    ) internal returns (bool) {
        require(_tokenAddress != address(0), 'Token address must different with NULL.');
        require(_amount > 0, 'Amount must greater than 0.');

        // Ensure agreement exists.
        if (registry.getLoanAssetToken().ownerOf(uint256(_agreementId)) != address(0)) {
            emit LogError(uint8(Errors.DEBT_AGREEMENT_NONEXISTENT), _agreementId);
            return false;
        }

        // Check payer has sufficient balance and has granted router sufficient allowance.
        if (
            IERC20(_tokenAddress).balanceOf(_payer) < _amount ||
            IERC20(_tokenAddress).allowance(_payer, address(this)) < _amount
        ) {
            emit LogError(uint8(Errors.PAYER_BALANCE_OR_ALLOWANCE_INSUFFICIENT), _agreementId);
            return false;
        }
        return true;
    }

    function _doRepay(
        bytes32 _agreementId,
        address _payer,
        uint256 _amount,
        address _tokenAddress
    ) internal returns (bool) {
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
            if (registry.getSecuritizationManager().isExistingPools(beneficiary))
                beneficiary = ISecuritizationPool(beneficiary).pot();
            require(
                IERC20(_tokenAddress).transferFrom(_payer, beneficiary, _amount - remains),
                'Unsuccessfully transferred repayment amount to Creditor.'
            );
        }

        // Log event for repayment
        emit LogRepayment(_agreementId, _payer, beneficiary, _amount, _tokenAddress);
        return true;
    }

    function repay(
        bytes32 agreementId,
        uint256 amount,
        address tokenAddress
    ) public override whenNotPaused nonReentrant returns (uint256) {
        require(
            _assertRepaymentRequest(agreementId, msg.sender, amount, tokenAddress),
            'LoanRepaymentRouter: Invalid repayment request'
        );
        require(_doRepay(agreementId, msg.sender, amount, tokenAddress), 'LoanRepaymentRouter: Repayment has failed');
        return amount;
    }

    function repayInBatch(
        bytes32[] calldata agreementIds,
        uint256[] calldata amounts,
        address tokenAddress
    ) external override whenNotPaused nonReentrant returns (bool) {
        for (uint256 i = 0; i < agreementIds.length; i++) {
            require(
                _assertRepaymentRequest(agreementIds[i], msg.sender, amounts[i], tokenAddress),
                'LoanRepaymentRouter: Invalid repayment request'
            );
            require(
                _doRepay(agreementIds[i], msg.sender, amounts[i], tokenAddress),
                'LoanRepaymentRouter: Repayment has failed'
            );
        }
        emit LogRepayments(agreementIds, msg.sender, amounts);
        return true;
    }
}
