// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../../../libraries/UnpackLoanParamtersLib.sol';
import '../../../constants/LoanTyping.sol';
import '../../../storage/Registry.sol';
import '../../../libraries/ConfigHelper.sol';
import '../LoanRegistry.sol';

contract LoanTermsContractBase is LoanTyping, UnpackLoanParamtersLib {
    using ConfigHelper for Registry;

    Registry public registry;

    uint256 public constant NUM_AMORTIZATION_UNIT_TYPES = 6;

    uint256 public constant YEAR_LENGTH_IN_DAYS = 365;
    // All time units in seconds
    uint256 public constant MINUTE_LENGTH_IN_SECONDS = 60;
    uint256 public constant HOUR_LENGTH_IN_SECONDS = MINUTE_LENGTH_IN_SECONDS * 60;
    uint256 public constant DAY_LENGTH_IN_SECONDS = HOUR_LENGTH_IN_SECONDS * 24;
    uint256 public constant WEEK_LENGTH_IN_SECONDS = DAY_LENGTH_IN_SECONDS * 7;
    uint256 public constant MONTH_LENGTH_IN_SECONDS = DAY_LENGTH_IN_SECONDS * 30;
    uint256 public constant YEAR_LENGTH_IN_SECONDS = DAY_LENGTH_IN_SECONDS * YEAR_LENGTH_IN_DAYS;

    // To convert an encoded interest rate into its equivalent in percents,
    // divide it by INTEREST_RATE_SCALING_FACTOR_PERCENT -- e.g.
    //     10,000 => 1% interest rate
    uint256 public constant INTEREST_RATE_SCALING_FACTOR_PERCENT = 10**4;

    // To convert an encoded interest rate into its equivalent multiplier
    // (for purposes of calculating total interest), divide it by INTEREST_RATE_SCALING_FACTOR_PERCENT -- e.g.
    //     10,000 => 0.01 interest multiplier
    uint256 public constant INTEREST_RATE_SCALING_FACTOR_MULTIPLIER = INTEREST_RATE_SCALING_FACTOR_PERCENT * 100;

    //////////////////////////////
    // EVENTS                 ///
    ////////////////////////////
    event LogInterestTermStart(
        bytes32 indexed agreementId,
        address indexed principalToken,
        uint256 principalAmount,
        uint256 interestRate,
        uint256 indexed amortizationUnitType,
        uint256 termLengthInAmortizationUnits
    );

    event LogRegisterRepayment(
        bytes32 agreementId,
        address payer,
        address beneficiary,
        uint256 unitsOfRepayment,
        address tokenAddress
    );

    event LogRegisterCompleteTerm(bytes32 agreementId);

    //////////////////////////////
    // MODIFIERS              ///
    ////////////////////////////
    modifier onlyRouter(LoanTypes loanType) {
        if (loanType == LoanTypes.EXTERNAL) {
            require(msg.sender == address(registry.getLoanRepaymentRouter()), 'Only for Repayment Router.');
        }
        _;
    }

    modifier onlyMappedToThisContract(LoanTypes loanType, bytes32 agreementId) {
        if (loanType == LoanTypes.EXTERNAL) {
            require(
                address(this) == LoanRegistry(registry.LoanRegistry()).getTermContract(agreementId),
                'Agreement Id is not belong to this Terms Contract.'
            );
        }
        _;
    }

    /** CONSTRUCTOR */
    function __LoanTermsContractBase_init(Registry _registry) public initializer {
        registry = _registry;
    }

    /////////////////////////
    // INTERNAL FUNCTIONS //
    ///////////////////////

    function _getAmortizationUnitLengthInSeconds(AmortizationUnitType amortizationUnitType)
        internal
        pure
        returns (uint256)
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
            revert('Unknown amortization unit type.');
        }
    }

    /**
     *   Get parameters by Agreement ID (commitment hash)
     */
    function _unpackParamsForAgreementID(LoanTypes loanType, bytes32 agreementId)
        internal
        view
        returns (InterestParams memory params)
    {
        bytes32 parameters;
        uint256 issuanceBlockTimestamp = 0;
        LoanRegistry loanRegistry = registry.getLoanRegistry();
        issuanceBlockTimestamp = loanRegistry.getIssuanceBlockTimestamp(agreementId);
        parameters = loanRegistry.getTermsContractParameters(agreementId);
        // Index of the token used for principal payments in the Token Registry
        uint256 principalTokenIndex;
        // The principal amount denominated in the aforementioned token.
        uint256 principalAmount;
        // The interest rate accrued per amortization unit.
        uint256 interestRate;
        // The amortization unit in which the repayments installments schedule is defined.
        uint256 rawAmortizationUnitType;
        // The debt's entire term's length, denominated in the aforementioned amortization units
        uint256 termLengthInAmortizationUnits;
        uint256 gracePeriodInDays;

        (
            principalTokenIndex,
            principalAmount,
            interestRate,
            rawAmortizationUnitType,
            termLengthInAmortizationUnits,
            gracePeriodInDays
        ) = _unpackLoanTermsParametersFromBytes(parameters);

        address principalTokenAddress = registry.getERC20TokenRegistry().getTokenAddressByIndex(principalTokenIndex);

        // Ensure that the encoded principal token address is valid
        require(principalTokenAddress != address(0), 'Invalid principal token address.');

        // Before we cast to `AmortizationUnitType`, ensure that the raw value being stored is valid.
        require(rawAmortizationUnitType <= uint256(AmortizationUnitType.YEARS), 'Amortization Unit Type is invalid.');

        AmortizationUnitType amortizationUnitType = AmortizationUnitType(rawAmortizationUnitType);

        // Calculate term length base on Amortization Unit and number
        uint256 termLengthInSeconds = termLengthInAmortizationUnits.mul(
            _getAmortizationUnitLengthInSeconds(amortizationUnitType)
        );

        return
            InterestParams({
                principalTokenIndex: principalTokenIndex,
                principalTokenAddress: principalTokenAddress,
                principalAmount: principalAmount,
                interestRate: interestRate,
                termStartUnixTimestamp: issuanceBlockTimestamp,
                termEndUnixTimestamp: termLengthInSeconds.add(issuanceBlockTimestamp),
                amortizationUnitType: amortizationUnitType,
                termLengthInAmortizationUnits: termLengthInAmortizationUnits
            });
    }

    // Calculate interest amount for a duration with specific Principal amount
    function _calculateInterestForDuration(
        uint256 _principalAmount,
        uint256 _interestRate,
        uint256 _durationLengthInSec
    ) internal pure returns (uint256) {
        return
            _principalAmount
                .mul(
                    ONE
                        .add(
                            _interestRate.mul(ONE / INTEREST_RATE_SCALING_FACTOR_PERCENT / 100).div(
                                YEAR_LENGTH_IN_SECONDS
                            )
                        )
                        .rpow(_durationLengthInSec, ONE)
                )
                .div(ONE)
                .sub(_principalAmount);
    }

    /**
     * Calculate values which Debtor need to pay to conclude current Loan
     */
    function _getExpectedRepaymentValuesToTimestamp(
        InterestParams memory _params,
        uint256 _lastRepaymentTimestamp, // timestamp of last repayment from debtor
        uint256 _timestamp,
        uint256 repaidPrincipalAmount,
        uint256 repaidInterestAmount,
        bool isManualInterestLoan,
        uint256 manualInterestAmountLoan
    ) internal pure returns (uint256 expectedPrinciapal, uint256 expectedInterest) {
        uint256 outstandingPrincipal = _params.principalAmount.sub(repaidPrincipalAmount);

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

    // Calculate interest amount Debtor need to pay until current date
    function _calculateInterestAmountToTimestamp(
        uint256 _principalAmount,
        uint256 _currentPrincipalAmount,
        uint256 _paidInterestAmount,
        uint256 _annualInterestRate,
        uint256 _startTermTimestamp,
        uint256 _endTermTimestamp,
        uint256 _lastRepayTimestamp,
        uint256 _timestamp
    ) internal pure returns (uint256) {
        if (_timestamp <= _startTermTimestamp) {
            return 0;
        }
        uint256 interest = 0;
        uint256 elapseTimeFromLastRepay = _timestamp.sub(_lastRepayTimestamp);
        uint256 elapseTimeFromStart = _timestamp.sub(_startTermTimestamp);

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
                interest = _calculateInterestForDuration(_principalAmount, _annualInterestRate, elapseTimeFromStart);
            }
        } else {
            interest = 0;
        }
        return interest;
    }

    function getStartDateInTimestamp(uint256 _timestamp) private pure returns (uint256) {
        uint256 secondInDay = _timestamp.mod(DAY_LENGTH_IN_SECONDS);
        return _timestamp.sub(secondInDay);
    }
}
