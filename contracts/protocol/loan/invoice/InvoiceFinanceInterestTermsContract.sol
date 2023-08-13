// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import './InvoiceDebtRegistry.sol';
import './InvoiceCollateralizer.sol';
import "../LoanTyping.sol";
import "../../../storage/Registry.sol";
import "./CRDecisionEngine.sol";
import "../../../libraries/Unpack16.sol";
import "../../../libraries/Unpack.sol";
import "../../../libraries/ConfigHelper.sol";

contract InvoiceFinanceInterestTermsContract is PausableUpgradeable, OwnableUpgradeable, CRDecisionEngine {
    using SafeMath for uint;
    using ConfigHelper for Registry;
    using Unpack for bytes32;
    using Unpack16 for bytes16;

    uint public constant NUM_AMORTIZATION_UNIT_TYPES = 6;

    uint public constant YEAR_LENGTH_IN_DAYS = 365;
    // All time units in seconds
    uint public constant MINUTE_LENGTH_IN_SECONDS = 60;
    uint public constant HOUR_LENGTH_IN_SECONDS = MINUTE_LENGTH_IN_SECONDS * 60;
    uint public constant DAY_LENGTH_IN_SECONDS = HOUR_LENGTH_IN_SECONDS * 24;
    uint public constant WEEK_LENGTH_IN_SECONDS = DAY_LENGTH_IN_SECONDS * 7;
    uint public constant MONTH_LENGTH_IN_SECONDS = DAY_LENGTH_IN_SECONDS * 30;
    uint public constant YEAR_LENGTH_IN_SECONDS = DAY_LENGTH_IN_SECONDS * YEAR_LENGTH_IN_DAYS;

    // To convert an encoded interest rate into its equivalent in percents,
    // divide it by INTEREST_RATE_SCALING_FACTOR_PERCENT -- e.g.
    //     10,000 => 1% interest rate
    uint public constant INTEREST_RATE_SCALING_FACTOR_PERCENT = 10 ** 4;

    // To convert an encoded interest rate into its equivalent multiplier
    // (for purposes of calculating total interest), divide it by INTEREST_RATE_SCALING_FACTOR_PERCENT -- e.g.
    //     10,000 => 0.01 interest multiplier
    uint public constant INTEREST_RATE_SCALING_FACTOR_MULTIPLIER = INTEREST_RATE_SCALING_FACTOR_PERCENT * 100;

    Registry public registry;

    enum AmortizationUnitType {
        MINUTES, // 0 - since 1.0.13
        HOURS, // 1
        DAYS, // 2
        WEEKS, // 3
        MONTHS, // 4
        YEARS // 5
    }

    struct InterestParams {
        uint256 principalAmount;
        uint256 termStartUnixTimestamp;
        uint256 termEndUnixTimestamp;
        AmortizationUnitType amortizationUnitType;
        uint256 termLengthInAmortizationUnits;
        // interest rates can, at a maximum, have 4 decimal places of precision.
        uint256 interestRate;
    }

    event LogInterestTermStart(
        bytes32 indexed agreementId,
        address indexed principalToken,
        uint principalAmount,
        uint interestRate,
        uint indexed amortizationUnitType,
        uint termLengthInAmortizationUnits
    );

    event LogRegisterRepayment(
        bytes32 agreementId,
        address payer,
        address beneficiary,
        uint256 unitsOfRepayment,
        address tokenAddress
    );

    event LogRegisterCompleteTerm (
        bytes32 agreementId
    );

    modifier onlyRouter() {
        require(
            msg.sender == address(registry.getInvoiceLoanRepaymentRouter()),
            "Only for Repayment Router."
        );
        _;
    }

    function initialize(Registry _registry) public initializer {
        __Pausable_init_unchained();
        __Ownable_init_unchained();
        registry = _registry;
    }


    function registerInvoiceLoanTermStart(bytes32 agreementId, address debtor)
        external
        returns (bool)
    {
        require(_msgSender() == address(registry.getInvoiceLoanKernel()), "InvoiceFinanceInterestTermsContract: only debt kernel");
        address termsContract;
        bytes32 termsContractParameters;

        (termsContract, termsContractParameters) = registry.getInvoiceDebtRegistry()
            .getTerms(agreementId);

        uint256 principalAmount = termsContractParameters.unpackPrincipalAmount();
        uint256 interestRate = termsContractParameters.unpackInterestRate();
        uint256 amortizationUnitType= termsContractParameters.unpackAmortizationUnitType();
        uint256 termLengthInAmortizationUnits= termsContractParameters.unpackTermLengthInAmortizationUnits();
        uint256 gracePeriodInDays= termsContractParameters.unpackGracePeriodInDays();

        address principalTokenAddress = registry.getInvoiceDebtRegistry().getAgreement(agreementId).principalTokenAddress;

        // Collateralize AIT token
        bool collateralized = registry.getInvoiceCollateralizer()
            .collateralizeERC721(agreementId, debtor);

        // Returns true (i.e. valid) if the specified principal token is valid,
        // the specified amortization unit type is valid, and the terms contract
        // associated with the agreement is this one.  We need not check
        // if any of the other simple interest parameters are valid, because
        // it is impossible to encode invalid values for them.
        if (
            principalTokenAddress != address(0) &&
            amortizationUnitType < NUM_AMORTIZATION_UNIT_TYPES &&
            termsContract == address(this) &&
            collateralized
        ) {
            emit LogInterestTermStart(
                agreementId,
                principalTokenAddress,
                principalAmount,
                interestRate,
                amortizationUnitType,
                termLengthInAmortizationUnits
            );

            return true;
        }

        return false;
    }

    /// When called, the registerRepayment function records the debtor's
    ///  repayment, as well as any auxiliary metadata needed by the contract
    ///  to determine ex post facto the value repaid (e.g. current USD
    ///  exchange rate)
    /// @param  agreementId bytes32. The agreement id (issuance hash) of the debt agreement to which this pertains.
    /// @param  payer address. The address of the payer.
    /// @param  beneficiary address. The address of the payment's beneficiary.
    /// @param  unitsOfRepayment uint. The units-of-value repaid in the transaction.
    /// @param  tokenAddress address. The address of the token with which the repayment transaction was executed.
    function registerRepayment(
        bytes32 agreementId,
        address payer,
        address beneficiary,
        uint256 unitsOfRepayment,
        address tokenAddress
    ) public onlyRouter() returns (uint256 remains) {
        InvoiceDebtRegistry invoiceDebtRegistry = registry.getInvoiceDebtRegistry();
        require(
            tokenAddress == invoiceDebtRegistry.getAgreement(agreementId).principalTokenAddress,
            'LoanTermsContract: Invalid token for repayment.'
        );
        // solium-disable-next-line
        uint256 currentTimestamp = block.timestamp;

        uint256 expectedPrincipal;
        uint256 expectedInterest;
        // query total outstanding amounts
        (expectedPrincipal, expectedInterest) = getExpectedRepaymentValues(
            agreementId,
            currentTimestamp
        );
        // TODO: Currently only allow Debtor to repay with amount >= expectedInterest of that time
        // Because, we haven't made any mechanism to manage outstanding interest amounts in the case when Debtor
        // repaid with amount < expectedInterest (at that moment)
        require(
            unitsOfRepayment >= expectedInterest,
            'LoanTermsContract: Expected interest amount is minimum.'
        );

        // exceed expectation, Debtor can pay all at once
        if (unitsOfRepayment >= expectedPrincipal.add(expectedInterest)) {
            invoiceDebtRegistry.setCompletedRepayment(agreementId);
            invoiceDebtRegistry.addRepaidInterestAmount(
                agreementId,
                expectedInterest
            );
            invoiceDebtRegistry.addRepaidPrincipalAmount(
                agreementId,
                expectedPrincipal
            );
            // put the remain to interest
            remains = unitsOfRepayment.sub(
                expectedPrincipal.add(expectedInterest)
            );
        } else {
            // if currently Debtor no need to repay for interest
            if (expectedInterest == 0) {
                if (unitsOfRepayment >= expectedPrincipal) {
                    invoiceDebtRegistry.addRepaidPrincipalAmount(
                        agreementId,
                        expectedPrincipal
                    );
                    // with the remains
                    if (unitsOfRepayment.sub(expectedPrincipal) > 0) {
                        invoiceDebtRegistry.addRepaidInterestAmount(
                            agreementId,
                            unitsOfRepayment.sub(expectedPrincipal)
                        );
                    }
                } else {
                    invoiceDebtRegistry.addRepaidPrincipalAmount(
                        agreementId,
                        unitsOfRepayment
                    );
                }
            } else {
                // if expectedInterest > 0 ( & unitsOfRepayment >= expectedInterest)
                invoiceDebtRegistry.addRepaidInterestAmount(
                    agreementId,
                    expectedInterest
                );
                if (unitsOfRepayment.sub(expectedInterest) > 0) {
                    // Debtor is not able to fulfill the expectedPrincipal as we already validated from first IF statement
                    // -> there is no remains for adding to repaidInterestAmount
                    invoiceDebtRegistry.addRepaidPrincipalAmount(
                        agreementId,
                        unitsOfRepayment.sub(expectedInterest)
                    );
                }
            }
        }

        // Update Debt registry record
        invoiceDebtRegistry.updateLastRepaymentTimestamp(
            agreementId,
            currentTimestamp
        );
        invoiceDebtRegistry.selfEvaluateCollateralRatio(agreementId);

        // Emit new event
        emit LogRegisterRepayment(
            agreementId,
            payer,
            beneficiary,
            unitsOfRepayment,
            tokenAddress
        );

        return remains;
    }

    /**
        * Function will be called by Debt Kernel, supports Debtor to deposit more invoice
        */
    function registerSecureLoanWithInvoice(
        bytes32 agreementId,
        address debtor,
        address collateral,
        bytes32[] memory invoiceTokenIds
    ) public returns (bool) {
        InvoiceDebtRegistry debtRegistry = registry.getInvoiceDebtRegistry();
        require(
            debtor == debtRegistry.getDebtor(agreementId),
            'Invalid debtor of agreement'
        );
        uint256 invoiceTokenIdLength = invoiceTokenIds.length;

        for (uint256 i = 0; i < invoiceTokenIdLength; i++) {
            // Sezie collateral tokens with addition amount
            bool collateralized = registry.getInvoiceCollateralizer()
                .additionERC721Collateralize(
                agreementId,
                debtor,
                invoiceTokenIds[i],
                collateral
            );

            if (collateralized) {
                // update terms contract parameters, then re evaluate CR
                debtRegistry.insertInvoiceFinancedToInvoiceLoan(
                    agreementId,
                    uint256(invoiceTokenIds[i])
                );
                debtRegistry.selfEvaluateCollateralRatio(agreementId);
            }
        }
        return true;
    }

    function registerInsecureLoanByWithdrawInvoice(
        bytes32 agreementId,
        address debtor,
        address collateral,
        bytes32[] memory invoiceTokenIds
    ) public returns (bool) {
        InvoiceDebtRegistry debtRegistry = registry.getInvoiceDebtRegistry();
        address debtorOfAgreement = debtRegistry.getDebtor(agreementId);
        require(debtor == debtorOfAgreement, 'Invalid debtor of agreement');
        uint256 invoiceTokenIdLength  = invoiceTokenIds.length;

        for (uint256 i = 0; i < invoiceTokenIdLength; i++) {
            // Sezie collateral tokens with addition amount
            bool collateralized = registry.getInvoiceCollateralizer()
                .withdrawERC721Collateralize(
                agreementId,
                debtor,
                invoiceTokenIds[i],
                collateral
            );

            if (collateralized) {
                // update terms contract parameters, then re evaluate CR
                debtRegistry.removeInvoiceId(
                    agreementId,
                    uint256(invoiceTokenIds[i])
                );
                debtRegistry.selfEvaluateCollateralRatio(agreementId);
            }

        }

        uint256 cr = debtRegistry.getCollateralRatio(agreementId);
        uint256 minCollateralRatio = debtRegistry.getMinCollateralRatio(
            agreementId
        );

        if (cr < minCollateralRatio) {
            revert(
                'InvoiceInterest: Invalid collateral ratio, bellow min collateral ratio'
            );
        }

        return true;
    }

    function registerConcludeInvoiceLoan(bytes32 agreementId)
        external
        returns (bool)
    {
        InvoiceDebtRegistry invoiceDebtRegistry = registry.getInvoiceDebtRegistry();
        require(
            invoiceDebtRegistry.isCompletedRepayment(agreementId),
            'Debtor has not completed repayment yet.'
        );
        require(
            registry.getInvoiceCollateralizer()
                .returnInvoiceCollateral(agreementId),
            'Unable to return AIT to its owner'
        );

        invoiceDebtRegistry.setCompletedLoan(agreementId);
        emit LogRegisterCompleteTerm(agreementId);
        return true;
    }

    function _unpackParamsForAgreementID(
        bytes32 agreementId
    )
    internal
    view
    returns (InterestParams memory params)
    {
        bytes32 parameters;
        uint issuanceBlockTimestamp = 0;

        InvoiceDebtRegistry invoiceDebtRegistry = registry.getInvoiceDebtRegistry();
        issuanceBlockTimestamp = invoiceDebtRegistry.getIssuanceBlockTimestamp(agreementId);
        parameters = invoiceDebtRegistry.getTermsContractParameters(agreementId);

        // The principal amount denominated in the aforementioned token.
        uint256 principalAmount = parameters.unpackPrincipalAmount();
        uint256 interestRate = parameters.unpackInterestRate();
        // The amortization unit in which the repayments installments schedule is defined.
        uint256 rawAmortizationUnitType= parameters.unpackAmortizationUnitType();
        // The debt's entire term's length, denominated in the aforementioned amortization units
        uint256 termLengthInAmortizationUnits= parameters.unpackTermLengthInAmortizationUnits();

        // Before we cast to `AmortizationUnitType`, ensure that the raw value being stored is valid.
        require(
            rawAmortizationUnitType <= uint(AmortizationUnitType.YEARS),
            "Amortization Unit Type is invalid."
        );

        AmortizationUnitType amortizationUnitType = AmortizationUnitType(rawAmortizationUnitType);

        // Calculate term length base on Amortization Unit and number
        uint termLengthInSeconds = termLengthInAmortizationUnits.mul(
            _getAmortizationUnitLengthInSeconds(amortizationUnitType)
        );

        return InterestParams({
            principalAmount: principalAmount,
            interestRate: interestRate,
            termStartUnixTimestamp: issuanceBlockTimestamp,
            termEndUnixTimestamp: termLengthInSeconds.add(issuanceBlockTimestamp),
            amortizationUnitType: amortizationUnitType,
            termLengthInAmortizationUnits: termLengthInAmortizationUnits
        });
    }

    function _getAmortizationUnitLengthInSeconds(AmortizationUnitType amortizationUnitType)
    internal
    pure
    returns (uint)
    {
        if (amortizationUnitType == AmortizationUnitType.MINUTES) {
            return MINUTE_LENGTH_IN_SECONDS;
        } else if (amortizationUnitType == AmortizationUnitType.HOURS) {
            return HOUR_LENGTH_IN_SECONDS;
        } else if (amortizationUnitType == AmortizationUnitType.DAYS) {
            return DAY_LENGTH_IN_SECONDS;
        } else if (amortizationUnitType == AmortizationUnitType.WEEKS) {
            return WEEK_LENGTH_IN_SECONDS;
        } else if (amortizationUnitType == AmortizationUnitType.MONTHS) {
            return MONTH_LENGTH_IN_SECONDS;
        } else if (amortizationUnitType == AmortizationUnitType.YEARS) {
            return YEAR_LENGTH_IN_SECONDS;
        } else {
            revert("Unknown amortization unit type.");
        }
    }
    /**
    * Expected repayment value with Amortization of Interest and Principal
    * (AMORTIZATION) - will be used for repayment from Debtor
    */
    function getExpectedRepaymentValues(bytes32 agreementId, uint256 timestamp)
        public
        view
        returns (uint256 expectedPrincipal, uint256 expectedInterest)
    {
        InterestParams memory params = _unpackParamsForAgreementID(agreementId);
        InvoiceDebtRegistry invoiceDebtRegistry = registry.getInvoiceDebtRegistry();

        uint256 repaidPrincipalAmount = invoiceDebtRegistry
            .getRepaidPrincipalAmount(agreementId);
        uint256 repaidInterestAmount = invoiceDebtRegistry
            .getRepaidInterestAmount(agreementId);
        uint256 lastRepaymentTimestamp = invoiceDebtRegistry
            .getLastRepaymentTimestamp(agreementId);

        bool isManualInterestLoan = invoiceDebtRegistry.isManualInterestLoan(
            agreementId
        );
        uint256 manualInterestAmountLoan;
        if (isManualInterestLoan) {
            manualInterestAmountLoan = invoiceDebtRegistry
                .getManualInterestAmountLoan(agreementId);
        }

        (
            expectedPrincipal,
            expectedInterest
        ) = _getExpectedRepaymentValuesToTimestamp(
            params,
            lastRepaymentTimestamp,
            timestamp,
            repaidPrincipalAmount,
            repaidInterestAmount,
            isManualInterestLoan,
            manualInterestAmountLoan
        );
    }

    /**
   * Calculate values which Debtor need to pay to conclude current Loan
   */
    function _getExpectedRepaymentValuesToTimestamp(
        InterestParams memory _params,
        uint _lastRepaymentTimestamp, // timestamp of last repayment from debtor
        uint _timestamp,
        uint repaidPrincipalAmount,
        uint repaidInterestAmount,
        bool isManualInterestLoan,
        uint manualInterestAmountLoan
    ) internal pure returns (uint expectedPrinciapal, uint expectedInterest) {
        uint outstandingPrincipal = _params.principalAmount.sub(repaidPrincipalAmount);

        expectedPrinciapal = outstandingPrincipal;

        if (isManualInterestLoan) {
            expectedInterest = manualInterestAmountLoan;
        } else {
            expectedInterest = _calculateInterestAmountToTimestamp(
                _params.principalAmount,
                outstandingPrincipal,
                repaidInterestAmount,
                _params.interestRate,
                _params.termStartUnixTimestamp,
                _params.termEndUnixTimestamp,
                _lastRepaymentTimestamp,
                _timestamp
            );
        }
    }

    // Calculate interest amount for a duration with specific Principal amount
    function _calculateInterestForDuration(
        uint _principalAmount,
        uint _interestRate,
        uint _durationLengthInSec
    ) internal pure returns (uint) {
        return _principalAmount.mul(_interestRate).mul(_durationLengthInSec.div(DAY_LENGTH_IN_SECONDS))
        .div(INTEREST_RATE_SCALING_FACTOR_MULTIPLIER).div(YEAR_LENGTH_IN_DAYS);
    }

    function getStartDateInTimestamp(uint _timestamp) private pure returns (uint) {
        uint secondInDay = _timestamp.mod(DAY_LENGTH_IN_SECONDS);
        return  _timestamp.sub(secondInDay);
    }

    // Calculate interest amount Debtor need to pay until current date
    function _calculateInterestAmountToTimestamp(
        uint _principalAmount,
        uint _currentPrincipalAmount,
        uint _paidInterestAmount,
        uint _annualInterestRate,
        uint _startTermTimestamp,
        uint _endTermTimestamp,
        uint _lastRepayTimestamp,
        uint _timestamp
    ) internal pure returns (uint) {
        if (_timestamp <= _startTermTimestamp) {
            return 0;
        }
        uint interest = 0;

        uint startOfDayOfLastRepay = getStartDateInTimestamp(_lastRepayTimestamp);
        uint startOfDayOfTermsStart = getStartDateInTimestamp(_startTermTimestamp);
        uint startOfDayToCalculateInterest = getStartDateInTimestamp(_timestamp);

        uint elapseTimeFromLastRepay = startOfDayToCalculateInterest.sub(startOfDayOfLastRepay);
        uint elapseTimeFromStart = startOfDayToCalculateInterest.sub(startOfDayOfTermsStart).add(DAY_LENGTH_IN_SECONDS);

        // If still within the term length
        if (_timestamp < _endTermTimestamp) {
            // Have just made new repayment
            if (elapseTimeFromLastRepay == 0 && _paidInterestAmount > 0) {
                interest = 0;
            } else {
                if (_paidInterestAmount > 0) {
                    // Has made at least 1 repayment
                    interest = _calculateInterestForDuration(
                        _currentPrincipalAmount,
                        _annualInterestRate,
                        elapseTimeFromLastRepay
                    );
                } else {
                    // Haven't made any repayment
                    interest = _calculateInterestForDuration(
                        _principalAmount,
                        _annualInterestRate,
                        elapseTimeFromStart
                    );
                }
            }

        } else if (_timestamp >= _endTermTimestamp) {
            // If debtor has made at least 1 repayment
            if (_paidInterestAmount > 0) {
                interest = _calculateInterestForDuration(
                    _currentPrincipalAmount,
                    _annualInterestRate,
                    elapseTimeFromLastRepay
                );
            } else {
                interest = _calculateInterestForDuration(
                    _principalAmount,
                    _annualInterestRate,
                    elapseTimeFromStart
                );
            }
        } else {
            interest = 0;
        }
        return interest;
    }

    function getValueRepaidToDate(bytes32 agreementId)
        public
        view
        returns (uint256, uint256)
    {
        return registry.getInvoiceDebtRegistry().getValueRepaidToDate(agreementId);
    }

    function isTermsContractExpired(bytes32 agreementId)
        public
        view
        returns (bool)
    {
        uint256 expTimestamp = registry.getInvoiceDebtRegistry()
            .getExpirationTimestamp(agreementId);
        // solium-disable-next-line
        if (expTimestamp <= block.timestamp) {
            return true;
        }
        return false;
    }

    /**
    * Function will be called by Debt Kernel, supports Debtor to deposit more collateral
    */
    function registerDrawdownLoan(
        bytes32 agreementId,
        uint256 drawdownAmount,
        bytes32 termsContractParameters
    ) public returns (bool) {
        // query current terms contract parameters
        InvoiceDebtRegistry debtRegistry = registry.getInvoiceDebtRegistry();
        require(
            drawdownAmount > 0,
            'Invoice Terms Contract: Drawdown amount must greater than 0.'
        );

        (, bytes32 currentTermsParameters) = debtRegistry.getTerms(agreementId);
        // validate new paramters, compare the amounts
        require(
            _validateNewTermsContractParamsDrawdown(
                currentTermsParameters,
                termsContractParameters,
                drawdownAmount
            ),
            'Invoice Terms Contract: Invalid terms contract parameters.'
        );
        require(
            _validateNewCollateralRatioWhenDrawdown(
                agreementId,
                drawdownAmount,
                debtRegistry
            ),
            'InvoiceInterest: Invalid collateral ratio, bellow min collateral ratio'
        );

        // update terms contract parameters, then re evaluate CR
        debtRegistry.updateLoanTermParameters(
            agreementId,
            termsContractParameters
        );
        debtRegistry.selfEvaluateCollateralRatio(agreementId);

        return true;
    }

    function _validateNewTermsContractParamsDrawdown(
        bytes32 _oldTermsContractParameters,
        bytes32 _newTermsContractParameters,
        uint _drawdownAmount
    ) internal pure returns (bool) {
        bool isValidPrincipalAmount = _newTermsContractParameters.unpackPrincipalAmount()
        .sub(_oldTermsContractParameters.unpackPrincipalAmount()) == _drawdownAmount;

        bool isInterestRateCorrect = _oldTermsContractParameters.unpackInterestRate()
        == _newTermsContractParameters.unpackInterestRate();

        bool isAmortizationUnitTypeCorrect = _oldTermsContractParameters.unpackAmortizationUnitType()
        == _newTermsContractParameters.unpackAmortizationUnitType();

        bool isTermLengthInAmortizationUnitsCorrect = _oldTermsContractParameters.unpackTermLengthInAmortizationUnits()
        == _newTermsContractParameters.unpackTermLengthInAmortizationUnits();

        bool isGracePeriodInDaysCorrect = _oldTermsContractParameters.unpackGracePeriodInDays()
        == _newTermsContractParameters.unpackGracePeriodInDays();

        return (
            isValidPrincipalAmount &&
            isInterestRateCorrect &&
            isAmortizationUnitTypeCorrect &&
            isTermLengthInAmortizationUnitsCorrect &&
            isGracePeriodInDaysCorrect
        );

    }

    function _validateNewCollateralRatioWhenDrawdown(
        bytes32 agreementId,
        uint256 _amountDrawdown,
        InvoiceDebtRegistry debtRegistry
    ) private view returns (bool) {
        uint256 collateralAmount = debtRegistry._getTotalInvoiceAmount(
            agreementId
        );
        uint256 currentTimestamp = block.timestamp;

        uint256 totalRemain = getTotalExpectedRepaymentValue(
            agreementId,
            currentTimestamp
        );
        uint256 cr = _computeInvoiceCR(
            collateralAmount,
            totalRemain + _amountDrawdown
        );

        uint256 minCollateralRatio = debtRegistry.getMinCollateralRatio(
            agreementId
        );

        if (cr < minCollateralRatio) {
            return false;
        }

        return true;
    }

    /**
    * Get TOTAL expected repayment value at specific timestamp
    * (NO AMORTIZATION)
    */
    function getTotalExpectedRepaymentValue(
        bytes32 agreementId,
        uint256 timestamp
    )
        public
        view
        returns (uint256 expectedRepaymentValue)
    {
        uint256 principalAmount;
        uint256 interestAmount;
        (principalAmount, interestAmount) = getExpectedRepaymentValues(
            agreementId,
            timestamp
        );
        expectedRepaymentValue = principalAmount.add(interestAmount);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}
