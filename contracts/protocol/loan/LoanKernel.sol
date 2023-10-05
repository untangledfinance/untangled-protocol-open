// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '../../interfaces/ILoanKernel.sol';
import '../../base/UntangledBase.sol';
import '../../libraries/ConfigHelper.sol';
import '../../libraries/UntangledMath.sol';

/// @title LoanKernel
/// @author Untangled Team
/// @notice Upload loan and conclude loan
contract LoanKernel is ILoanKernel, UntangledBase {
    using ConfigHelper for Registry;

    function initialize(Registry _registry) public initializer {
        __UntangledBase__init_unchained(_msgSender());

        registry = _registry;
    }

    modifier validFillingOrderAddresses(address[] memory _orderAddresses) {
        require(_orderAddresses[uint8(FillingAddressesIndex.CREDITOR)] != address(0x0), 'CREDITOR is zero address.');
        require(
            _orderAddresses[uint8(FillingAddressesIndex.REPAYMENT_ROUTER)] != address(0x0),
            'REPAYMENT_ROUTER is zero address.'
        );
        require(
            _orderAddresses[uint8(FillingAddressesIndex.TERM_CONTRACT)] != address(0x0),
            'TERM_CONTRACT is zero address.'
        );
        require(
            _orderAddresses[uint8(FillingAddressesIndex.PRINCIPAL_TOKEN_ADDRESS)] != address(0x0),
            'PRINCIPAL_TOKEN_ADDRESS is zero address.'
        );
        _;
    }

    //******************** */
    // PRIVATE FUNCTIONS
    //******************** */

    /**
     * Helper function that constructs a issuance structs from the given
     * parameters.
     */
    function _getIssuance(
        address[] memory _orderAddresses,
        address[] memory _debtors,
        bytes32[] memory _termsContractParameters,
        uint256[] memory _salts
    ) private pure returns (LoanIssuance memory _issuance) {
        LoanIssuance memory issuance = LoanIssuance({
            version: _orderAddresses[uint8(FillingAddressesIndex.REPAYMENT_ROUTER)],
            debtors: _debtors,
            termsContract: _orderAddresses[uint8(FillingAddressesIndex.TERM_CONTRACT)],
            termsContractParameters: _termsContractParameters,
            salts: _salts,
            agreementIds: _genLoanAgreementIds(
                _orderAddresses[uint8(FillingAddressesIndex.REPAYMENT_ROUTER)],
                _debtors,
                _orderAddresses[uint8(FillingAddressesIndex.TERM_CONTRACT)],
                _termsContractParameters,
                _salts
            )
        });

        return issuance;
    }

    function _getDebtOrderHashes(LoanOrder memory debtOrder) private view returns (bytes32[] memory) {
        uint256 _length = debtOrder.issuance.debtors.length;
        bytes32[] memory orderHashses = new bytes32[](_length);
        for (uint256 i = 0; i < _length; i = UntangledMath.uncheckedInc(i)) {
            orderHashses[i] = _getDebtOrderHash(
                debtOrder.issuance.agreementIds[i],
                debtOrder.principalAmounts[i],
                debtOrder.principalTokenAddress,
                debtOrder.relayer,
                debtOrder.expirationTimestampInSecs[i]
            );
        }
        return orderHashses;
    }

    function _getLoanOrder(
        address[] memory _debtors,
        address[] memory _orderAddresses,
        uint256[] memory _orderValues,
        bytes32[] memory _termContractParameters,
        uint256[] memory _salts
    ) private view returns (LoanOrder memory _debtOrder) {
        bytes32[] memory emptyDebtOrderHashes = new bytes32[](_debtors.length);
        LoanOrder memory debtOrder = LoanOrder({
            issuance: _getIssuance(_orderAddresses, _debtors, _termContractParameters, _salts),
            relayer: _orderAddresses[uint8(FillingAddressesIndex.RELAYER)],
            principalTokenAddress: _orderAddresses[uint8(FillingAddressesIndex.PRINCIPAL_TOKEN_ADDRESS)],
            principalAmounts: _principalAmountsFromOrderValues(_orderValues, _termContractParameters.length),
            creditorFee: _orderValues[uint8(FillingNumbersIndex.CREDITOR_FEE)],
            expirationTimestampInSecs: _expirationTimestampsFromOrderValues(
                _orderValues,
                _termContractParameters.length
            ),
            debtOrderHashes: emptyDebtOrderHashes,
            riskScores: _riskScoresFromOrderValues(_orderValues, _termContractParameters.length),
            assetPurpose: uint8(_orderValues[uint8(FillingNumbersIndex.ASSET_PURPOSE)])
        });
        debtOrder.debtOrderHashes = _getDebtOrderHashes(debtOrder);
        return debtOrder;
    }

    //** Issue Loan to Farmers */
    function _issueDebtAgreements(
        bytes32 latTokenId,
        address creditor,
        address termContract,
        address debtor,
        bytes32 termsParam,
        address principalTokenAddress,
        uint256 salt,
        uint256 expirationTimestampInSecs,
        uint8[] memory assetPurposeAndRiskScore
    ) private {
        // Mint debt tokens and finalize debt agreement

        registry.getLoanAssetToken().safeMint(creditor, uint256(latTokenId));

        require(
            registry.getLoanRegistry().insert(
                latTokenId,
                termContract,
                debtor,
                termsParam,
                principalTokenAddress,
                salt,
                expirationTimestampInSecs,
                assetPurposeAndRiskScore
            ),
            'AcceptedInvoiceToken: insert failure'
        );
    }

    /**
     * 6 is fixed size of constant addresses list
     */
    function _debtorsFromOrderAddresses(address[] memory _orderAddresses, uint256 _length)
        private
        pure
        returns (address[] memory)
    {
        address[] memory debtors = new address[](_length);
        for (uint256 i = 5; i < (5 + _length); i = UntangledMath.uncheckedInc(i)) {
            debtors[i - 5] = _orderAddresses[i];
        }
        return debtors;
    }

    // Dettach principal amounts from order values
    function _principalAmountsFromOrderValues(uint256[] memory _orderValues, uint256 _length)
        private
        pure
        returns (uint256[] memory)
    {
        uint256[] memory principalAmounts = new uint256[](_length);
        for (uint256 i = 2; i < (2 + _length); i = UntangledMath.uncheckedInc(i)) {
            principalAmounts[i - 2] = _orderValues[i];
        }
        return principalAmounts;
    }

    function _expirationTimestampsFromOrderValues(uint256[] memory _orderValues, uint256 _length)
        private
        pure
        returns (uint256[] memory)
    {
        uint256[] memory expirationTimestamps = new uint256[](_length);
        for (uint256 i = 2 + _length; i < (2 + _length * 2); i = UntangledMath.uncheckedInc(i)) {
            expirationTimestamps[i - 2 - _length] = _orderValues[i];
        }
        return expirationTimestamps;
    }

    function _saltFromOrderValues(uint256[] memory _orderValues, uint256 _length)
        private
        pure
        returns (uint256[] memory)
    {
        uint256[] memory salts = new uint256[](_length);
        for (uint256 i = 2 + _length * 2; i < (2 + _length * 3); i = UntangledMath.uncheckedInc(i)) {
            salts[i - 2 - _length * 2] = _orderValues[i];
        }
        return salts;
    }

    function _riskScoresFromOrderValues(uint256[] memory _orderValues, uint256 _length)
        private
        pure
        returns (uint8[] memory)
    {
        uint8[] memory riskScores = new uint8[](_length);
        for (uint256 i = 2 + _length * 3; i < (2 + _length * 4); i = UntangledMath.uncheckedInc(i)) {
            riskScores[i - 2 - _length * 3] = uint8(_orderValues[i]);
        }
        return riskScores;
    }

    function _getAssetPurposeAndRiskScore(uint8 assetPurpose, uint8 riskScore) private pure returns (uint8[] memory) {
        uint8[] memory assetPurposeAndRiskScore = new uint8[](2);
        assetPurposeAndRiskScore[0] = assetPurpose;
        assetPurposeAndRiskScore[1] = riskScore;
        return assetPurposeAndRiskScore;
    }

    function _burnLoanAssetToken(bytes32 agreementId) private {
        registry.getLoanAssetToken().burn(uint256(agreementId));
    }

    function _assertDebtExisting(bytes32 agreementId) private view returns (bool) {
        return registry.getLoanAssetToken().ownerOf(uint256(agreementId)) != address(0);
    }

    function _assertCompletedRepayment(bytes32 agreementId) private view returns (bool) {
        return registry.getLoanInterestTermsContract().completedRepayment(agreementId);
    }

    /// @inheritdoc ILoanKernel
    /// @dev A loan, stop lending/loan terms or allow the loan loss
    function concludeLoan(
        address creditor,
        bytes32 agreementId,
        address termContract
    ) public override whenNotPaused {
        require(creditor != address(0), 'Invalid creditor account.');
        require(agreementId != bytes32(0), 'Invalid agreement id.');
        require(termContract != address(0), 'Invalid terms contract.');

        if (!_assertDebtExisting(agreementId) || !_assertCompletedRepayment(agreementId)) {
            revert('Debt does not exsits or Debtor have not completed repayment.');
        }

        require(
            ILoanInterestTermsContract(termContract).registerConcludeLoan(agreementId),
            'Cannot register conclude loan.'
        );
        _burnLoanAssetToken(agreementId);
    }

    /*********************** */
    // EXTERNAL FUNCTIONS
    /*********************** */

    function concludeLoans(
        address[] calldata creditors,
        bytes32[] calldata agreementIds,
        address termContract
    ) external whenNotPaused nonReentrant {
        uint256 creditorsLength = creditors.length;
        for (uint256 i = 0; i < creditorsLength; i = UntangledMath.uncheckedInc(i)) {
            concludeLoan(creditors[i], agreementIds[i], termContract);
        }
    }

    /**
     * Filling new Debt Order
     * Notice:
     * - All Debt Order must to have same:
     *   + TermContract
     *   + Creditor Fee
     *   + Debtor Fee
     */
    function fillDebtOrder(
        address[] calldata orderAddresses, // 0-creditor, 1-principal token address, 2-repayment router, 3-term contract, 4-relayer,...
        uint256[] calldata orderValues, //  0-creditorFee, 1-asset purpose,..., [x] principalAmounts, [x] expirationTimestampInSecs, [x] - salts, [x] - riskScores
        bytes32[] calldata termsContractParameters, // Term contract parameters from different farmers, encoded as hash strings
        bytes32[] calldata tokenIds // [x]-Loan liability token Id, [x]-Loan liability token Id
    ) external whenNotPaused nonReentrant validFillingOrderAddresses(orderAddresses) {
        require(termsContractParameters.length > 0, 'LoanKernel: Invalid Term Contract params');

        uint256[] memory salts = _saltFromOrderValues(orderValues, termsContractParameters.length);
        LoanOrder memory debtOrder = _getLoanOrder(
            _debtorsFromOrderAddresses(orderAddresses, termsContractParameters.length),
            orderAddresses,
            orderValues,
            termsContractParameters,
            salts
        );

        uint256 agreementIdsLength = debtOrder.issuance.agreementIds.length;
        for (uint256 i = 0; i < agreementIdsLength; i = UntangledMath.uncheckedInc(i)) {
            require(debtOrder.issuance.agreementIds[i] == tokenIds[i], 'LoanKernel: Invalid LAT Token Id');

            _issueDebtAgreements(
                tokenIds[i],
                orderAddresses[uint8(FillingAddressesIndex.CREDITOR)],
                orderAddresses[uint8(FillingAddressesIndex.TERM_CONTRACT)],
                debtOrder.issuance.debtors[i],
                termsContractParameters[i],
                debtOrder.principalTokenAddress,
                salts[i],
                debtOrder.expirationTimestampInSecs[i],
                _getAssetPurposeAndRiskScore(debtOrder.assetPurpose, debtOrder.riskScores[i])
            );

            require(
                ILoanInterestTermsContract(debtOrder.issuance.termsContract).registerTermStart(tokenIds[i]),
                'Cannot register term start'
            );

            emit LogDebtOrderFilled(
                debtOrder.issuance.agreementIds[i],
                debtOrder.principalAmounts[i],
                debtOrder.principalTokenAddress,
                debtOrder.relayer
            );
        }
    }

    function _getDebtOrderHash(
        bytes32 agreementId,
        uint256 principalAmount,
        address principalTokenAddress,
        address relayer,
        uint256 expirationTimestampInSec
    ) private view returns (bytes32 _debtorMessageHash) {
        return
            keccak256(
                abi.encodePacked(
                    address(this),
                    agreementId,
                    principalAmount,
                    principalTokenAddress,
                    relayer,
                    expirationTimestampInSec
                )
            );
    }

    function _genLoanAgreementIds(
        address _version,
        address[] memory _debtors,
        address _termsContract,
        bytes32[] memory _termsContractParameters,
        uint256[] memory _salts
    ) private pure returns (bytes32[] memory) {
        bytes32[] memory agreementIds = new bytes32[](_salts.length);
        for (uint256 i = 0; i < (0 + _salts.length); i = UntangledMath.uncheckedInc(i)) {
            agreementIds[i] = keccak256(
                abi.encodePacked(_version, _debtors[i], _termsContract, _termsContractParameters[i], _salts[i])
            );
        }
        return agreementIds;
    }

    uint256[50] private __gap;
}
