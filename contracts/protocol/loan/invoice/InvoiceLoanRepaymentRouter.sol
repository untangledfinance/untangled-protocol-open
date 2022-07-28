// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./InvoiceFinanceInterestTermsContract.sol";
import "./InvoiceDebtRegistry.sol";
import "../../../storage/Registry.sol";
import '@openzeppelin/contracts/interfaces/IERC20.sol';

/**
* The RepaymentRouter routes allowers payers to make repayments on any
* given debt agreement in any given token by routing the payments to
* the debt agreement's beneficiary.  Additionally, the router acts
* as a trusted oracle to the debt agreement's terms contract, informing
* it of exactly what payments have been made in what quantity and in what token.
*/
contract InvoiceLoanRepaymentRouter is PausableUpgradeable, OwnableUpgradeable {

    using ConfigHelper for Registry;
    Registry public registry;

    enum Errors {
        DEBT_AGREEMENT_NONEXISTENT,
        PAYER_BALANCE_OR_ALLOWANCE_INSUFFICIENT,
        REPAYMENT_REJECTED_BY_TERMS_CONTRACT
    }

    event LogRepayment(
        bytes32 indexed _agreementId,
        address indexed _payer,
        address indexed _beneficiary,
        uint _amount,
        address _token
    );

    event LogError(uint8 indexed _errorId, bytes32 indexed _agreementId);

    function initialize(Registry _registry) public initializer {
        __Pausable_init_unchained();
        __Ownable_init_unchained();
        registry = _registry;
    }

    // Validate repayment request parametters
    function _assertRepaymentRequest(bytes32 _agreementId, address _payer, uint256 _amount, address _tokenAddress)
        internal view
    {
        require(_tokenAddress != address(0), "Token address must different with NULL.");
        require(_amount > 0, "Amount must greater than 0.");

        // Ensure agreement exists.
        require(
            registry.getInvoiceDebtRegistry().doesEntryExist(_agreementId),
            "Inventory Debt Registry: Agreement Id does not exists."
        );
    }


    function _doRepay(bytes32 _agreementId, address _payer, uint256 _amount, address _tokenAddress)
        internal
    {
        // Notify terms contract
        InvoiceDebtRegistry invoiceDebtRegistry = registry.getInvoiceDebtRegistry();
        address termsContract = invoiceDebtRegistry.getTermsContract(_agreementId);
        address beneficiary = invoiceDebtRegistry.getBeneficiary(_agreementId);
        address debtor = invoiceDebtRegistry.getDebtor(_agreementId);

        uint remains = InvoiceFinanceInterestTermsContract(termsContract).registerRepayment(
            _agreementId,
            _payer,
            beneficiary,
            _amount,
            _tokenAddress
        );

        // Transfer amount to creditor
        require(
            IERC20(_tokenAddress).transferFrom(_payer, beneficiary, _amount - remains),
            "Unsuccessfully transferred repayment amount to Creditor.");

        // Transfer remain amount to debtor
        if (debtor != _payer && remains > 0) {
            require(
                IERC20(_tokenAddress).transferFrom(_payer, debtor, remains),
                "Unsuccessfully transferred remain repayment amount to Debtor."
            );
        }

        // Log event for repayment
        emit LogRepayment(_agreementId, _payer, beneficiary, _amount, _tokenAddress);
    }


    /**
     */
    function repayFromInvoicePayment(
        bytes32 agreementId,
        address payer,
        uint256 amount,
        address tokenAddress
    )
        public
        whenNotPaused
        returns (uint)
    {
        _assertRepaymentRequest(agreementId, payer, amount, tokenAddress);
        _doRepay(agreementId, payer, amount, tokenAddress);
        return amount;
    }

    // Mannual repay by using Fiat tokens
    function repay(bytes32 agreementId, address payer, uint256 amount, address tokenAddress)
        public
        whenNotPaused
        returns (uint)
    {
        _assertRepaymentRequest(agreementId, payer, amount, tokenAddress);
        _doRepay(agreementId, payer, amount, tokenAddress);
        return amount;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}
