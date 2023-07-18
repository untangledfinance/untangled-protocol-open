// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/interfaces/IERC20.sol';
import './InventoryInterestTermsContract.sol';
import '../../cma/SupplyChainManagementProgram.sol';
import './InventoryLoanRegistry.sol';
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract InventoryLoanKernel is PausableUpgradeable, OwnableUpgradeable {
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
        bytes16 collateralInfoParameters;
        uint256 salt;
        bytes32 agreementId;
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
        address priceFeedOperator;
        uint256 minCollateralRatio;
        uint256 liquidationRatio;
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

    /**
     * Helper function that constructs a hashed debt order struct given the raw parameters
     * of a debt order.
     */
    function _getDebtOrder(
        address[6] memory orderAddresses,
        uint256[7] memory orderValues,
        bytes32[1] memory orderBytes32,
        bytes16[1] memory orderBytes16
    ) internal view returns (DebtOrder memory _debtOrder) {
        DebtOrder memory debtOrder = DebtOrder({
            issuance: _getIssuance(
                orderAddresses[0],
                orderAddresses[1],
                orderAddresses[2],
                orderValues[0],
                orderBytes32[0],
                orderBytes16[0]
            ),
            principalToken: orderAddresses[3],
            relayer: orderAddresses[4],
            principalAmount: orderValues[1],
            creditorFee: orderValues[2],
            debtorFee: orderValues[3],
            expirationTimestampInSec: orderValues[4],
            debtOrderHash: bytes32(0),
            priceFeedOperator: orderAddresses[5],
            minCollateralRatio: orderValues[5],
            liquidationRatio: orderValues[6]
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
        bytes16 _collateralInfoParameters
    ) internal pure returns (Issuance memory _issuance) {
        Issuance memory issuance = Issuance({
            version: _version,
            debtor: _debtor,
            termsContract: _termsContract,
            salt: _salt,
            termsContractParameters: _termsContractParameters,
            collateralInfoParameters: _collateralInfoParameters,
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

    /**
     * Helper function that mints LAT associated with the
     * given issuance and grants it to the beneficiary (creditor).
     */
    function _issueDebtAgreement(
        address beneficiary,
        DebtOrder memory debtOrder
    ) internal returns (bytes32) {
        uint256[4] memory valueParams = [
            debtOrder.minCollateralRatio,
            debtOrder.liquidationRatio,
            debtOrder.expirationTimestampInSec,
            debtOrder.issuance.salt
        ];
        //
        InventoryLoanRegistry debtRegistry = registry.getInventoryLoanRegistry();
        bytes32 entryHash = debtRegistry.insert(
            debtOrder.issuance.version,
            beneficiary,
            debtOrder.issuance.debtor,
            debtOrder.issuance.termsContract,
            debtOrder.priceFeedOperator,
            debtOrder.principalToken,
            debtOrder.issuance.termsContractParameters,
            debtOrder.issuance.collateralInfoParameters,
            valueParams
        );

        registry.getLoanAssetToken().mint(beneficiary, uint256(entryHash));

        //
        require(
            entryHash == debtOrder.issuance.agreementId,
            "Newly minted token's Id is different with agreement Id."
        );

        return (debtOrder.issuance.agreementId);
    }

    function _burnLoanAssetToken(address creditor, bytes32 agreementId)
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
        return IERC20(token).balanceOf(owner);
    }

    /**
     * Helper function for querying an address' allowance to the 0x transfer proxy.
     */
    function _getAllowance(address token, address owner)
        internal
        view
        returns (uint256 _allowance)
    {
        // Limit gas to prevent reentrancy.
        return IERC20(token).allowance(owner, address(this));
    }

    /**
     * Given a hashed message, a signer's address, and a signature, returns
     * whether the signature is valid.
     */
    function _isValidSignature(
        address signer,
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (bool _valid) {
        return
            signer ==
            ecrecover(
                keccak256(
                    abi.encodePacked('\x19Ethereum Signed Message:\n32', hash)
                ),
                v,
                r,
                s
            );
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
        return IERC20(token).transferFrom(from, to, amount);
    }

    /**
     * Asserts that debt order meets all validity requirements described in
     * the Kernel specification document.
     */
    function _assertDebtOrderValidityInvariants(DebtOrder memory debtOrder)
        internal
        returns (bool _orderIsValid)
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
     * Asserts that a debt order meets all consensuality requirements
     * described in the DebtKernel specification document.
     */
    function _assertDebtOrderConsensualityInvariants(
        DebtOrder memory debtOrder,
        address creditor,
        uint8[2] memory signaturesV,
        bytes32[2] memory signaturesR,
        bytes32[2] memory signaturesS
    ) internal returns (bool _orderIsConsensual) {
        // Invariant: debtor's signature must be valid, unless debtor is submitting order
        if (msg.sender != debtOrder.issuance.debtor) {
            if (
                !_isValidSignature(
                    debtOrder.issuance.debtor,
                    debtOrder.debtOrderHash,
                    signaturesV[0],
                    signaturesR[0],
                    signaturesS[0]
                )
            ) {
                return false;
            }
        }

        // Invariant: creditor's signature must be valid, unless creditor is submitting order
        if (msg.sender != creditor) {
            if (
                !_isValidSignature(
                    creditor,
                    debtOrder.debtOrderHash,
                    signaturesV[1],
                    signaturesR[1],
                    signaturesS[1]
                )
            ) {
                return false;
            }
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
        // TODO change to InventoryLoanRegistry
        return registry.getInventoryLoanRegistry().completedRepayment(agreementId);
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

        InventoryInterestTermsContract(termContract)
            .registerConcludeTerm(agreementId);

        _burnLoanAssetToken(creditor, agreementId);

        (uint256 collateralId, ) = registry.getInventoryLoanRegistry()
            .getCollateralInfoParameters(agreementId);
        registry.getSupplyChainManagementProgram()
            .removeAgreementFromCommodity(collateralId, agreementId);
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

    function getSignatureRS()
        internal
        pure
        returns (bytes32[2] memory signatures)
    {
        bytes32[2] memory signaturesRS;
        return signaturesRS;
    }

    function getSignatureV()
        internal
        pure
        returns (uint8[2] memory signatures)
    {
        uint8[2] memory signaturesV;
        return signaturesV;
    }

    function _fillDebtOrder(
        address creditor,
        address buyer,
        uint256 principalAmount,
        address[6] calldata orderAddresses, // 1-repayment router, 2-debtor, 3-termcontract, 4-principalTokenAddress, 5-relayer, 6-priceFeeOperator, 7-creditor
        uint256[7] calldata orderValues, // 1-salt, 2-principalAmount, 3-creditorFee, 4-debtorFee, 5-expirationTimestampInSec, 6-minCR, 7-liquidationRatio
        bytes32[1] calldata orderBytes32, // 1-termsContractParameters
        bytes16[1] calldata orderBytes16, // 1-collateralInfoParameters
        address[5] calldata debtorFeeBeneficiaries,
        address[5] calldata creditorFeeBeneficiaries,
        uint256[5] calldata debtorFeeAmounts,
        uint256[5] calldata creditorFeeAmounts
    ) external whenNotPaused returns (bytes32 _agreementId) {
        address[6] memory _orderAddresses = orderAddresses;
        _orderAddresses[1] = buyer;
        uint256[7] memory _orderValues = orderValues;
        _orderValues[1] = principalAmount;

        return
            fillDebtOrder(
                creditor,
                _orderAddresses,
                _orderValues,
                orderBytes32,
                orderBytes16,
                getSignatureV(),
                getSignatureRS(),
                getSignatureRS(),
                debtorFeeBeneficiaries,
                creditorFeeBeneficiaries,
                debtorFeeAmounts,
                creditorFeeAmounts
            );
    }

    function getAssetHolder(DebtOrder memory debtOrder)
        internal
        view
        returns (address _assetHolder)
    {
/*
        bool isEmbeddedFlow = EReceiptInventoryTradeFactory(
            contractRegistry.get(E_RECEIPT_INVENTORY_TRADE_FACTORY)
        )
            .isExistedTrade(msg.sender);
        address assetHolder = isEmbeddedFlow
            ? msg.sender
            : debtOrder.issuance.debtor;
*/

        return debtOrder.issuance.debtor;
    }

    ////////////////////////
    // EXTERNAL FUNCTIONS //
    ////////////////////////

    /**
     * Fills a given debt order if it is valid and consensual.
     */
    function fillDebtOrder(
        address creditor,
        address[6] memory orderAddresses, // 1-repayment router, 2-debtor, 3-termcontract, 4-principalTokenAddress, 5-relayer, 6-priceFeeOperator
        uint256[7] memory orderValues, // 1-salt, 2-principalAmount, 3-creditorFee, 4-debtorFee, 5-expirationTimestampInSec, 6-minCR, 7-liquidationRatio
        bytes32[1] memory orderBytes32, // 1-termsContractParameters
        bytes16[1] memory orderBytes16, // 1-collateralInfoParameters
        uint8[2] memory signaturesV, // 1-debtorSignatureV, 2-creditorSignatureV
        bytes32[2] memory signaturesR, // 1-debtorSignatureR, 2-creditorSignatureR
        bytes32[2] memory signaturesS, // 1-debtorSignatureS, 2-creditorSignatureS,
        address[5] memory debtorFeeBeneficiaries,
        address[5] memory creditorFeeBeneficiaries,
        uint256[5] memory debtorFeeAmounts,
        uint256[5] memory creditorFeeAmounts
    ) public whenNotPaused returns (bytes32 _agreementId) {
        DebtOrder memory debtOrder = _getDebtOrder(
            orderAddresses,
            orderValues,
            orderBytes32,
            orderBytes16
        );

        //_assertDebtOrderConsensualityInvariants
        if (!_assertDebtOrderValidityInvariants(debtOrder)) {
            revert('InventoryLoanDebtKernel: Invalid Debt Order');
        }

        // Mint debt token and finalize debt agreement
        _issueDebtAgreement(creditor, debtOrder);

        // Register debt agreement's start with terms contract
        // We permit terms contracts to be undefined (for debt agreements which
        // may not have terms contracts associated with them), and only
        // register a term's start if the terms contract address is defined.
        if (debtOrder.issuance.termsContract != address(0x0)) {
            require(
                InventoryInterestTermsContract(debtOrder.issuance.termsContract)
                    .registerTermStart(
                    debtOrder.issuance.agreementId,
                    [debtOrder.issuance.debtor, getAssetHolder(debtOrder)]
                ),
                'Register terms start was failed.'
            );
        }

        // Transfer principal to debtor
        if (debtOrder.principalAmount > 0) {
            require(
                _transferTokensFrom(
                    debtOrder.principalToken,
                    creditor,
                    getAssetHolder(debtOrder),
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

        // require(false, 'checkpoint DEBT_KERNEL REGISTER_TERM_START_1');

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
            creditorFeeBeneficiaries,
            creditorFeeAmounts
        );

        _transferFeesToBeneficiaries(
            debtOrder.issuance.debtor,
            creditor, // because deducted directly from principal amount
            debtOrder.principalToken,
            debtorFeeBeneficiaries,
            debtorFeeAmounts
        );

        (uint256 collateralId, ) = registry.getInventoryLoanRegistry()
            .getCollateralInfoParameters(debtOrder.issuance.agreementId);
        registry.getSupplyChainManagementProgram()
            .insertAgreementToCommodity(
            collateralId,
            debtOrder.issuance.agreementId
        );

        emit LogDebtOrderFilled(
            debtOrder.issuance.agreementId,
            debtOrder.principalAmount,
            debtOrder.principalToken,
            debtOrder.relayer
        );

        return debtOrder.issuance.agreementId;
    }

    /**
     * Debtor call to complete this Debt whenever he thinks that he completed all repayment
     */
    function concludeLoan(
        address creditor,
        bytes32 agreementId,
        address termContract
    ) public whenNotPaused {
        _concludeLoan(creditor, agreementId, termContract);
    }

    /**
     *
     */
    function secureLoanWithCollateral(
        bytes32 agreementId,
        address termsContract,
        address debtor,
        uint256 amount,
        address collateral,
        bytes16 collateralInfoParameters
    ) public whenNotPaused {
        InventoryInterestTermsContract(termsContract)
            .registerSecureLoanWithCollateral(
            agreementId,
            debtor,
            amount,
            collateral,
            collateralInfoParameters
        );
    }

    /**
     * Allows a debtor to cancel a debt order before it's been filled
     * -- preventing any counterparty from filling it in the future.
     */
    function cancelDebtOrder(
        address[6] memory orderAddresses,
        uint256[7] memory orderValues,
        bytes32[1] memory orderBytes32,
        bytes16[1] memory orderBytes16
    ) public whenNotPaused {
        DebtOrder memory debtOrder = _getDebtOrder(
            orderAddresses,
            orderValues,
            orderBytes32,
            orderBytes16
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
        bytes16 collateralInfoParameters,
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

    function _isParticipantOfProject(
        uint256 projectId,
        address trader,
        address lender,
        address executor
    ) private view returns (bool) {
        SupplyChainManagementProgram supplyChainManagementProgram = registry.getSupplyChainManagementProgram();
        if (
            supplyChainManagementProgram.isTrader(projectId, trader) &&
            supplyChainManagementProgram.isLender(projectId, lender) &&
            supplyChainManagementProgram.isExecutor(projectId, executor)
        ) {
            return true;
        }
        return false;
    }

    /**
     * Trader sell cma collateral
     */
    function sellCollateral(
        bytes32 agreementId,
        uint256 projectId,
        uint256 amountCollateral,
        uint256 price,
        uint256 fiatTokenIndex,
        address collateral,
        bytes16 collateralInfoParameters,
        address[3] memory participantAddresses, // 1-debtor, 2-approval(creditor), 3-executor
        uint8[3] memory signaturesV, // 1-debtorSignatureV, 2-creditorSignatureV, 3-executorSignatureV
        bytes32[3] memory signaturesR, // 1-debtorSignatureR, 2-creditorSignatureR, 3-executorSignatureR
        bytes32[3] memory signaturesS // 1-debtorSignatureS, 2-creditorSignatureS, 3-executorSignatureS
    ) public whenNotPaused {
        // TODO: validate participant from project, remove to get rid of versioning
        //        require(
        //            _isParticipantOfProject(projectId, participantAddresses[0], participantAddresses[1], participantAddresses[2]),
        //            "Participant is not valid in project"
        //        );

        //_assertDebtOrderConsensualityInvariants check signature

        registry.getInventoryInterestTermsContract()
            .registerSellCollateral(
            agreementId,
            amountCollateral,
            price,
            fiatTokenIndex,
            collateral,
            collateralInfoParameters
        );
    }

    /**
     * Buyer pay the cma collateral by fiat
     */
    function payCollateralByFiat(
        bytes32 agreementId,
        bytes32 sellCollateralId,
        address payer
    ) public whenNotPaused {
        registry.getInventoryInterestTermsContract()
            .registerPayCollateralByFiat(
            agreementId,
            sellCollateralId,
            payer
        );
    }

    /**
     * Buyer pay the cma collateral by invoice
     */
    function payCollateralByInvoice(
        bytes32 agreementId,
        bytes32 sellCollateralId,
        address payer,
        uint256 dueDate,
        uint256 salt
    ) public whenNotPaused returns (uint256) {
        require(msg.sender == payer, 'InventoryLoanDebtKernel: Invalid payer');

        uint256 aitTokenId = registry.getInventoryInterestTermsContract()
            .registerPayCollateralByInvoice(
            agreementId,
            sellCollateralId,
            payer,
            dueDate,
            salt
        );

        require(
            aitTokenId != 0,
            'Register sell collateral by invoice was failed.'
        );
        return aitTokenId;
    }

    /**
     * Debtor withdraw collateral when CR is still safe
     */
    function insecureLoanByWithdrawCollateral(
        bytes32 agreementId,
        address termsContract,
        uint256 amount,
        address collateral,
        bytes16 collateralInfoParameters
    ) public whenNotPaused {
        InventoryInterestTermsContract(termsContract)
            .registerInsecureLoanByWithdrawCollateral(
            agreementId,
            msg.sender,
            amount,
            collateral,
            collateralInfoParameters
        );
    }

    /**
     * Creditor foreclosure if loan is expired or meet the liquidation ratio
     */
    function foreclosureLoanBySellCollateral(
        bytes32 agreementId,
        uint256 projectId,
        uint256 amountCollateral,
        uint256 price,
        uint256 fiatTokenIndex,
        address collateral,
        bytes16 collateralInfoParameters,
        uint8 signaturesV, // executorSignatureV
        bytes32 signaturesR, // executorSignatureR
        bytes32 signaturesS // executorSignatureS
    ) public whenNotPaused {
        //_assertDebtOrderConsensualityInvariants check signature
        //        require(
        //            SupplyChainManagementProgram(contractRegistry.get(SUPPLY_CHAIN_MANAGEMENT_PROGRAM)).isExecutor(projectId, executor),
        //            "InventoryLoanDebtKernel: Invalid executor");

        require(
            msg.sender ==
                    registry.getInventoryLoanRegistry()
                    .getBeneficiary(agreementId),
            'InventoryLoanDebtKernel: Invalid creditor'
        );

        registry.getInventoryInterestTermsContract()
            .registerForeclosureLoan(agreementId);

        registry.getInventoryInterestTermsContract()
            .registerSellCollateral(
            agreementId,
            amountCollateral,
            price,
            fiatTokenIndex,
            collateral,
            collateralInfoParameters
        );
    }

    function drawdownLoan(
        bytes32 agreementId,
        uint256 drawdownAmount,
        bytes32 termsContractParameters,
        uint8[2] memory signaturesV, // 1-debtorSignatureV, 2-creditorSignatureV
        bytes32[2] memory signaturesR, // 1-debtorSignatureR, 2-creditorSignatureR
        bytes32[2] memory signaturesS // 1-debtorSignatureS, 2-creditorSignatureS
    ) public whenNotPaused {
        //_assertDebtOrderConsensualityInvariants check signature

        InventoryLoanRegistry inventoryLoanDebtRegistry = registry.getInventoryLoanRegistry();
        //        require(
        //            msg.sender == inventoryLoanDebtRegistry.getBeneficiary(agreementId),
        //            "InventoryLoanDebtKernel: Invalid creditor"
        //        );
        //        require(
        //            msg.sender == inventoryLoanDebtRegistry.getDebtor(agreementId),
        //            "InventoryLoanDebtKernel: Invalid debtor"
        //        );
        require(
            inventoryLoanDebtRegistry.doesEntryExist(agreementId),
            'Agreement not existed'
        );

        registry.getInventoryInterestTermsContract().registerDrawdownLoan(
            agreementId,
            drawdownAmount,
            termsContractParameters
        );

        // Transfer drawdown amount to debtor
        address creditor = inventoryLoanDebtRegistry.getBeneficiary(
            agreementId
        );
        address debtor = inventoryLoanDebtRegistry.getDebtor(agreementId);
        address fiatTokenAddress = inventoryLoanDebtRegistry.getAgreement(agreementId).principalTokenAddress;
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
            'InventoryLoanDebtKernel: Unsuccessfully transferred drawdown amount to Debtor.'
        );
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}
