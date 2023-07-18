// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import './InvoiceFinanceInterestTermsContract.sol';
import './InvoiceDebtRegistry.sol';
import "./Registry.sol";
import '@openzeppelin/contracts/interfaces/IERC20.sol';
import "../ConfigHelper.sol";

/**
 * The InvoiceLoanDebtKernel is the hub of all business logic governing how and when
 * debt orders can be filled and cancelled.  All logic that determines
 * whether a debt order is valid & consensual is contained herein,
 * as well as the mechanisms that transfer fees to keepers and
 * principal payments to debtors.
 *
 */
contract InvoiceLoanKernel is PausableUpgradeable, OwnableUpgradeable {
    using SafeMath for uint256;
    using ConfigHelper for Registry;

    Registry registry;

    bytes32 public constant NULL_ISSUANCE_HASH = bytes32(0);

    /* NOTE: Currently, the `view` keyword does not actually enforce the
    static nature of the method; this will change in the future, but for now, in
    order to prevent reentrancy we'll need to arbitrarily set an upper bound on
    the gas limit allotted for certain method calls. */
    uint16 public constant EXTERNAL_QUERY_GAS_LIMIT = 8000;

    mapping(bytes32 => bool) public issuanceCancelled;
    mapping(bytes32 => bool) public debtOrderCancelled;
    mapping(bytes32 => bool) public debtOrderCompleted;

    mapping(bytes32 => bytes32) public agreementToLiability;

    ///////////////////////////
    // EVENTS
    ///////////////////////////

    event LogDebtOrderFilled(
        bytes32 indexed _agreementId,
        uint256 _principal,
        address _principalToken,
        address _relayer
    );

    event LogIssuanceCancelled(
        bytes32 indexed _agreementId,
        address indexed _cancelledBy
    );

    event LogDebtOrderCancelled(
        bytes32 indexed _debtOrderHash,
        address indexed _cancelledBy
    );

    event LogFeeTransfer(
        address indexed payer,
        address token,
        uint256 amount,
        address indexed beneficiary
    );

    struct Issuance {
        address version;
        address debtor;
        address termsContract;
        bytes32 termsContractParameters;
        bytes32[] invoiceTokenIds;
        bytes32 agreementId;
        uint256 salt;
    }

    struct DebtOrder {
        Issuance issuance;
        uint256 principalAmount;
        address principalToken;
        uint256 creditorFee;
        uint256 debtorFee;
        address relayer;
        uint256 expirationTimestampInSec;
        bytes32 debtOrderHash;
        uint256 minCollateralRatio;
    }

    function initialize(Registry _registry) public initializer {
        __Pausable_init_unchained();
        __Ownable_init_unchained();
        registry = _registry;
    }

    ////////////////////////
    // INTERNAL FUNCTIONS //
    ////////////////////////

    /**
     * Returns the hash of the debt order.
     */
    function _getDebtOrderHash(DebtOrder memory debtOrder)
        internal
        view
        returns (bytes32 _debtorMessageHash)
    {
        return
            keccak256(
                abi.encodePacked(
                    address(this),
                    debtOrder.issuance.agreementId,
                    debtOrder.principalAmount,
                    debtOrder.principalToken,
                    debtOrder.debtorFee,
                    debtOrder.creditorFee,
                    debtOrder.relayer,
                    debtOrder.expirationTimestampInSec
                )
            );
    }

    function getInvoiceTokenIds(bytes32[] memory orderBytes32)
        internal
        pure
        returns (bytes32[] memory)
    {
        bytes32[] memory invoiceTokenIds = new bytes32[](
            orderBytes32.length - 1
        );
        for (uint256 i = 0; i < invoiceTokenIds.length; i++) {
            invoiceTokenIds[i] = orderBytes32[i + 1];
        }
        return invoiceTokenIds;
    }

    /**
     * Helper function that constructs a hashed debt order struct given the raw parameters
     * of a debt order.
     */
    function _getDebtOrder(
        address[5] memory orderAddresses, // 0-repayment router, 1-debtor, 2-termcontract, 3-principalTokenAddress, 4-relayer
        uint256[6] memory orderValues, // 0-salt, 1-principalAmount, 2-creditorFee, 3-debtorFee, 4-expirationTimestampInSec, 5-minCR
        bytes32[] memory orderBytes32
    ) internal view returns (DebtOrder memory _debtOrder) {
        DebtOrder memory debtOrder = DebtOrder({
            issuance: _getIssuance(
                orderAddresses[0],
                orderAddresses[1],
                orderAddresses[2],
                orderValues[0],
                orderBytes32[0],
                getInvoiceTokenIds(orderBytes32)
            ),
            principalToken: orderAddresses[3],
            relayer: orderAddresses[4],
            principalAmount: orderValues[1],
            creditorFee: orderValues[2],
            debtorFee: orderValues[3],
            expirationTimestampInSec: orderValues[4],
            debtOrderHash: bytes32(0),
            minCollateralRatio: orderValues[5]
        });

        debtOrder.debtOrderHash = _getDebtOrderHash(debtOrder);

        return debtOrder;
    }

    /**
     * Helper function that returns an issuance's hash
     */
    function _getAgreementId(
        address version,
        address debtor,
        address termsContract,
        uint256 salt,
        bytes32 termsContractParameters
    ) internal pure returns (bytes32 _agreementId) {
        return
            keccak256(
                abi.encodePacked(
                    version,
                    debtor,
                    termsContract,
                    termsContractParameters,
                    salt
                )
            );
    }

    /**
     * Helper function that constructs a hashed issuance structs from the given
     * parameters.
     */
    function _getIssuance(
        address _version,
        address _debtor,
        address _termsContract,
        uint256 _salt,
        bytes32 _termsContractParameters,
        bytes32[] memory _invoiceTokenIds
    ) internal pure returns (Issuance memory _issuance) {
        Issuance memory issuance = Issuance({
            version: _version,
            debtor: _debtor,
            termsContract: _termsContract,
            salt: _salt,
            termsContractParameters: _termsContractParameters,
            invoiceTokenIds: _invoiceTokenIds,
            agreementId: _getAgreementId(
                _version,
                _debtor,
                _termsContract,
                _salt,
                _termsContractParameters
            )
        });

        return issuance;
    }

    function _burnLoanAssetToken(bytes32 agreementId)
        internal
    {
        registry.getLoanAssetToken().burn(uint256(agreementId));
    }

    /**
     * Helper function for querying an address' balance on a given token.
     */
    function _getBalance(address token, address owner)
        internal
        view
        returns (uint256 _balance)
    {
        // Limit gas to prevent reentrancy.
        return ERC20(token).balanceOf(owner);
    }

    /**
     * Helper function transfers a specified amount of tokens between two parties
     * using the token transfer proxy contract.
     */
    function _transferTokensFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal returns (bool success) {
        return
            IERC20(token)
                .transferFrom(from, to, amount);
    }

    /**
     * Asserts that debt order meets all validity requirements described in
     * the Kernel specification document.
     */
    function _assertDebtOrderValidityInvariants(DebtOrder memory debtOrder)
        internal view
        returns (bool)
    {
        // Validate fee amount
        // uint totalFees = debtOrder.creditorFee.add(debtOrder.debtorFee);
        // Invariant: debtor is given enough principal to cover at least debtorFees
        if (debtOrder.principalAmount < debtOrder.debtorFee) {
            return false;
        }
        // Invariant: debt order must not be expired
        // solhint-disable-next-line not-rely-on-time
        if (debtOrder.expirationTimestampInSec < block.timestamp) {
            return false;
        }
        // Invariant: debt order's issuance must not have been cancelled
        if (issuanceCancelled[debtOrder.issuance.agreementId]) {
            return false;
        }
        // Invariant: debt order itself must not have been cancelled
        if (debtOrderCancelled[debtOrder.debtOrderHash]) {
            return false;
        }
        return true;
    }

    /**
    *
    */
    function _assertDebtExisting(bytes32 agreementId)
        internal
        view
        returns (bool)
    {
        return registry.getLoanAssetToken().ownerOf(uint256(agreementId)) != address(0);
    }

    /**
    */
    function _assertCompletedRepayment(bytes32 agreementId)
        internal
        view
        returns (bool)
    {
        return
                registry.getInvoiceDebtRegistry()
                .isCompletedRepayment(agreementId);
    }

    //Conclude a loan, stop lending/loan terms or allow the loan loss
    function _concludeLoan(
        address creditor,
        bytes32 agreementId,
        address termContract
    ) internal {
        require(creditor != address(0), 'Invalid creditor account.');
        require(agreementId != bytes32(0), 'Invalid agreement id.');
        require(termContract != address(0), 'Invalid terms contract.');

        if (
            !_assertDebtExisting(agreementId) ||
            !_assertCompletedRepayment(agreementId)
        ) {
            revert(
                'Debt does not exsits or Debtor have not completed repayment.'
            );
        }

        // bool isTermCompleted = true;
        bool isTermCompleted = InvoiceFinanceInterestTermsContract(termContract)
            .registerConcludeInvoiceLoan(agreementId);

        if (isTermCompleted) {
            _burnLoanAssetToken(agreementId);
        } else {
            revert('Unable to conclude terms contract.');
        }
    }

    // Transfer fee to beneficiaries
    function _transferFeesToBeneficiaries(
        address payer,
        address from,
        address token,
        address[5] memory beneficiaries,
        uint256[5] memory amounts
    ) internal {
        for (uint256 i = 0; i < amounts.length; i++) {
            if (amounts[i] > 0 && beneficiaries[i] != address(0x0)) {
                _transferTokensFrom(token, from, beneficiaries[i], amounts[i]);
                emit LogFeeTransfer(payer, token, amounts[i], beneficiaries[i]);
            }
        }
    }

    function _sumTotalFees(uint256[5] memory amounts)
        internal
        pure
        returns (uint256)
    {
        uint256 totalAmount;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount = totalAmount.add(amounts[i]);
        }
        return totalAmount;
    }

    ////////////////////////
    // EXTERNAL FUNCTIONS //
    ////////////////////////

    /**
    * Debtor call to complete this Debt whenever he thinks that he completed all repayment
    */
    function concludeLoan(
        address creditor,
        address debtor,
        bytes32 agreementId,
        address termContract
    ) public whenNotPaused {
        _concludeLoan(creditor, agreementId, termContract);
    }

    /**
     * Allows a debtor to cancel a debt order before it's been filled
     * -- preventing any counterparty from filling it in the future.
     */
    function cancelDebtOrder(
        address[5] memory orderAddresses,
        uint256[6] memory orderValues,
        bytes32[] memory orderBytes32
    ) public whenNotPaused {
        DebtOrder memory debtOrder = _getDebtOrder(
            orderAddresses,
            orderValues,
            orderBytes32
        );

        require(
            msg.sender == debtOrder.issuance.debtor,
            "Debtor cancelation's requestor must be the Debtor."
        );

        debtOrderCancelled[debtOrder.debtOrderHash] = true;

        emit LogDebtOrderCancelled(debtOrder.debtOrderHash, msg.sender);
    }

    /**
     * Allows debtors to prevent a debt issuance in which they're involved from being used in
     * a future debt order.
     */
    function cancelIssuance(
        address version,
        address debtor,
        address termsContract,
        bytes32 termsContractParameters,
        bytes32[] memory collateralInfoParameters,
        uint256 salt
    ) public whenNotPaused {
        require(
            msg.sender == debtor,
            "Issuance cancelation's requestor must be the Debtor."
        );

        Issuance memory issuance = _getIssuance(
            version,
            debtor,
            termsContract,
            salt,
            termsContractParameters,
            collateralInfoParameters
        );

        issuanceCancelled[issuance.agreementId] = true;

        emit LogIssuanceCancelled(issuance.agreementId, msg.sender);
    }

    function getDebtorCreditorFeeBeneficiaries(
        address[10] memory feeBeneficiaries,
        bool isDebtor
    ) internal pure returns (address[5] memory result) {
        uint256 dataMargin = isDebtor ? 0 : 5;
        for (uint8 i = 0; i < result.length; i++) {
            result[i] = feeBeneficiaries[i + dataMargin];
        }
    }

    function getDebtorCreditorFeeAmounts(
        uint256[10] memory feeAmounts,
        bool isDebtor
    ) internal pure returns (uint256[5] memory result) {
        uint256 dataMargin = isDebtor ? 0 : 5;
        for (uint8 i = 0; i < result.length; i++) {
            result[i] = feeAmounts[i + dataMargin];
        }
    }

    function _transferTokensLoanIssuance(
        DebtOrder memory debtOrder,
        address creditor,
        address[10] memory feeBeneficiaries,
        uint256[10] memory feeAmounts
    ) internal {
        uint256[5] memory debtorFeeAmounts = getDebtorCreditorFeeAmounts(
            feeAmounts,
            true
        );

        // Transfer principal to debtor
        if (debtOrder.principalAmount > 0) {
            require(
                _transferTokensFrom(
                    debtOrder.principalToken,
                    creditor,
                    debtOrder.issuance.debtor,
                    debtOrder.principalAmount.sub(
                        _sumTotalFees(debtorFeeAmounts).add(debtOrder.debtorFee)
                    )
                ),
                'Unable to transfer principal tokens to Debtor.'
            );
        }

        // Transfer debtorFee to relayer
        if (debtOrder.debtorFee > 0) {
            require(
                _transferTokensFrom(
                    debtOrder.principalToken,
                    creditor, // because creditor is the person who approved Tranfer Proxy to transfer, not Debtor
                    debtOrder.relayer,
                    debtOrder.debtorFee
                ),
                "Unable to transfer debtor's fee to Relayer."
            );
            emit LogFeeTransfer(
                debtOrder.issuance.debtor,
                debtOrder.principalToken,
                debtOrder.debtorFee,
                debtOrder.relayer
            );
        }

        // Transfer debtorFee to relayer
        if (debtOrder.creditorFee > 0) {
            require(
                _transferTokensFrom(
                    debtOrder.principalToken,
                    creditor,
                    debtOrder.relayer,
                    debtOrder.creditorFee
                ),
                "Unable to transfer creditor's fee to Relayer."
            );
            emit LogFeeTransfer(
                creditor,
                debtOrder.principalToken,
                debtOrder.creditorFee,
                debtOrder.relayer
            );
        }

        _transferFeesToBeneficiaries(
            creditor,
            creditor,
            debtOrder.principalToken,
            getDebtorCreditorFeeBeneficiaries(feeBeneficiaries, false),
            getDebtorCreditorFeeAmounts(feeAmounts, false)
        );

        _transferFeesToBeneficiaries(
            debtOrder.issuance.debtor,
            creditor, // because deducted directly from principal amount
            debtOrder.principalToken,
            getDebtorCreditorFeeBeneficiaries(feeBeneficiaries, true),
            debtorFeeAmounts
        );
    }

    // Modify financing status of AIT
/*
    function _changeInvoiceFinancingState(
        bytes32[] memory _tokenIds,
        bytes32 _agreementId
    ) internal {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            AcceptedInvoiceToken ait = registry.getAcceptedInvoiceToken();
            ait.beginFinancing(_tokenIds[i], _agreementId);
        }
    }
*/

    /**
     * Helper function that mints LAT associated with the
     * given issuance and grants it to the beneficiary (creditor).
     */
    function _issueDebtAgreement(
        address beneficiary,
        DebtOrder memory debtOrder
    ) internal {
        uint256[3] memory valueParams = [
            debtOrder.minCollateralRatio,
            debtOrder.expirationTimestampInSec,
            debtOrder.issuance.salt
        ];

        InvoiceDebtRegistry debtRegistry = registry.getInvoiceDebtRegistry();
        bytes32 entryHash = debtRegistry.insert(
            debtOrder.issuance.version, // version
            beneficiary, // beneficiary
            debtOrder.issuance.debtor, // debtor
            debtOrder.issuance.termsContract, // term contract
            debtOrder.principalToken,
            debtOrder.issuance.termsContractParameters,
            debtOrder.issuance.invoiceTokenIds,
            valueParams
        );
        registry.getLoanAssetToken().mint(beneficiary, uint256(entryHash));

        require(
            entryHash == debtOrder.issuance.agreementId,
            "Newly minted token's Id is different with agreement Id."
        );
    }

    /**
     * Fills a given debt order if it is valid and consensual.
     */
    function fillDebtOrder(
        address creditor,
        address[5] calldata orderAddresses, // 0-repayment router, 1-debtor, 2-termcontract, 3-principalTokenAddress, 4-relayer
        uint256[6] calldata orderValues, // 0-salt, 1-principalAmount, 2-creditorFee, 3-debtorFee, 4-expirationTimestampInSec, 5-minCR
        bytes32[] calldata orderBytes32, // 0-termsContractParameters, 1-x -invoiceTokenIdBytes32
        uint8[2] calldata signaturesV, // 1-debtorSignatureV, 2-creditorSignatureV
        bytes32[2] calldata signaturesR, // 1-debtorSignatureR, 2-creditorSignatureR
        bytes32[2] calldata signaturesS, // 1-debtorSignatureS, 2-creditorSignatureS,
        address[10] calldata feeBeneficiaries,
        uint256[10] calldata feeAmounts
    ) external whenNotPaused returns (bytes32 _agreementId) {
        DebtOrder memory debtOrder = _getDebtOrder(
            orderAddresses,
            orderValues,
            orderBytes32
        );

        //_assertDebtOrderConsensualityInvariants
        if (!_assertDebtOrderValidityInvariants(debtOrder)) {
            revert('InvoiceLoanDebtKernel: Invalid debt order or lacking of approval');
        }

        // Mint debt token and finalize debt agreement
        _issueDebtAgreement(creditor, debtOrder);

        // Register debt agreement's start with terms contract
        // We permit terms contracts to be undefined (for debt agreements which
        // may not have terms contracts associated with them), and only
        // register a term's start if the terms contract address is defined.
        if (debtOrder.issuance.termsContract != address(0x0)) {
            require(
                InvoiceFinanceInterestTermsContract(
                    debtOrder
                        .issuance
                        .termsContract
                )
                    .registerInvoiceLoanTermStart(
                    debtOrder.issuance.agreementId,
                    debtOrder.issuance.debtor
                ),
                'Register terms start was failed.'
            );
        }

        _transferTokensLoanIssuance(
            debtOrder,
            creditor,
            feeBeneficiaries,
            feeAmounts
        );

/*
        _changeInvoiceFinancingState(
            debtOrder.issuance.invoiceTokenIds,
            debtOrder.issuance.agreementId
        );
*/

        emit LogDebtOrderFilled(
            debtOrder.issuance.agreementId,
            debtOrder.principalAmount,
            debtOrder.principalToken,
            debtOrder.relayer
        );

        return debtOrder.issuance.agreementId;
    }

    function drawdownLoan(
        bytes32 agreementId,
        uint256 drawdownAmount,
        bytes32 termsContractParameters,
        uint8[2] memory signaturesV, // 1-debtorSignatureV, 2-creditorSignatureV
        bytes32[2] memory signaturesR, // 1-debtorSignatureR, 2-creditorSignatureR
        bytes32[2] memory signaturesS // 1-debtorSignatureS, 2-creditorSignatureS
    ) public whenNotPaused {
        //_assertDebtOrderConsengualityInvariants check signature

        InvoiceDebtRegistry invoiceDebtRegistry = registry.getInvoiceDebtRegistry();
        require(
            invoiceDebtRegistry.doesEntryExist(agreementId),
            'Agreement not existed'
        );

        require(
                registry.getInvoiceFinanceInterestTermsContract()
                .registerDrawdownLoan(
                agreementId,
                drawdownAmount,
                termsContractParameters
            ),
            'Register drawdown was failed'
        );

        // Transfer drawdown amount to debtor
        address creditor = invoiceDebtRegistry.getBeneficiary(agreementId);
        address debtor = invoiceDebtRegistry.getDebtor(agreementId);
        address fiatTokenAddress = invoiceDebtRegistry.getAgreement(agreementId).principalTokenAddress;
        require(
            fiatTokenAddress != address(0),
            'Token address must different with NULL.'
        );

        require(
            IERC20(fiatTokenAddress)
                .transferFrom(
                creditor,
                debtor,
                drawdownAmount
            ),
            'Unsuccessfully transferred drawdown amount to Debtor.'
        );
    }

    function secureLoanWithInvoice(
        bytes32 agreementId,
        address termsContract,
        address debtor,
        address collateral,
        bytes32[] memory invoiceTokenIds
    ) public whenNotPaused {

        require(
            InvoiceFinanceInterestTermsContract(termsContract)
                .registerSecureLoanWithInvoice(
                agreementId,
                debtor,
                collateral,
                invoiceTokenIds
            ),
            'InvoiceFinanceInterestTermsContract: Register secure loan with invoice was failed.'
        );

//        _changeInvoiceFinancingState(invoiceTokenIds, agreementId);
    }

    function insecureLoanByWithdrawInvoice(
        bytes32 agreementId,
        address termsContract,
        address collateral,
        bytes32[] memory invoiceTokenIds
    ) public whenNotPaused {

        require(
            InvoiceFinanceInterestTermsContract(termsContract)
                .registerInsecureLoanByWithdrawInvoice(
                agreementId,
                msg.sender,
                collateral,
                invoiceTokenIds
            ),
            'InvoiceFinanceInterestTermsContract: Register insecure loan by withdraw invoice was failed.'
        );
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}
