pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract UnpackLoanParamtersLib {
    using SafeMath for uint256;
    using SafeMath for uint128;

    struct InterestParams {
        uint principalTokenIndex;
        address principalTokenAddress;
        uint principalAmount;
        uint termStartUnixTimestamp;
        uint termEndUnixTimestamp;
        AmortizationUnitType amortizationUnitType;
        uint termLengthInAmortizationUnits;
        // interest rates can, at a maximum, have 4 decimal places of precision.
        uint interestRate;
    }

    enum AmortizationUnitType {
        MINUTES, // 0 - since 1.0.13
        HOURS, // 1
        DAYS,  // 2
        WEEKS, // 3
        MONTHS, // 4
        YEARS  // 5
    }

    /**
    *
    * Notice: * uint256 (a) reinterprets a as 256-bit unsigned integer. As long as 256 bit = 32 bytes
    */
    function _bitShiftRight(bytes32 value, uint amount)
        internal
        pure
        returns (uint)
    {
        return uint(value) / 2 ** amount;
    }

    /**
    * uint128 (a) reinterprets a as 128-bit unsigned integer. As long as 128 bit = 16 bytes
    */
    function _bitShiftRight16(bytes16 value, uint amount)
        internal
        pure
        returns (uint)
    {
        return uint128(value) / 2 ** amount;
    }

    function _bitShiftLeft16(uint value, uint amount)
        internal
        pure
        returns (bytes16)
    {
        return bytes16(uint128(value * 2 ** amount));
    }

    /**
    */
    function _unpackCollateralParametersFromBytes(bytes16 collateralParams)
        internal
        pure
        returns (uint, uint)
    {
        bytes16 collateralTokenIndexShifted = collateralParams & 0xff000000000000000000000000000000;
        bytes16 collateralAmountShifted = collateralParams & 0x00ffffffffffffffffffffffff000000;

        return (
            _bitShiftRight16(collateralTokenIndexShifted, 120),
            _bitShiftRight16(collateralAmountShifted, 24)
        );
    }

    function _packCollateralParametersFromBytes(uint collateralTokenIndex, uint collateralAmount)
        internal pure returns (bytes16) {
        bytes16 collateralTokenIndexShifted = _bitShiftLeft16(collateralTokenIndex, 120) & 0xff000000000000000000000000000000;
        bytes16 collateralAmountShifted = _bitShiftLeft16(collateralAmount, 24) & 0x00ffffffffffffffffffffffff000000;

        return collateralTokenIndexShifted | collateralAmountShifted;
    }

    /**
    */
    function _unpackInventoryCollateralParametersFromBytes(bytes16 collateralParams)
        internal
        pure
        returns (uint, uint)
    {
        bytes16 collateralTokenIdShifted = collateralParams & 0xffffffff000000000000000000000000;
        bytes16 collateralAmountShifted = collateralParams & 0x00000000ffffffffffffffffffffffff;

        return (
            _bitShiftRight16(collateralTokenIdShifted, 96),
            _bitShiftRight16(collateralAmountShifted, 0)
        );
    }

   /**
    * Unpack parameters from packed bytes32 data
    */
    function _unpackLoanTermsParametersFromBytes(bytes32 parameters)
        internal
        pure
        returns (
            uint _principalTokenIndex,
            uint _principalAmount,
            uint _interestRate,
            uint _amortizationUnitType,
            uint _termLengthInAmortizationUnits,
            uint _gracePeriodInDays
        )
    {
        // The first byte of the parameters encodes the principal token's index in the
        // token registry.
        bytes32 principalTokenIndexShifted = parameters & 0xff00000000000000000000000000000000000000000000000000000000000000;
        // The subsequent 12 bytes of the parameters encode the PRINCIPAL AMOUNT.
        bytes32 principalAmountShifted = parameters & 0x00ffffffffffffffffffffffff00000000000000000000000000000000000000;
        // The subsequent 3 bytes of the parameters encode the INTEREST RATE.
        bytes32 interestRateShifted = parameters & 0x00000000000000000000000000ffffff00000000000000000000000000000000;
        // The subsequent 4 bits (half byte) encode the AMORTIZATION UNIT TYPE code.
        bytes32 amortizationUnitTypeShifted = parameters & 0x00000000000000000000000000000000f0000000000000000000000000000000;
        // The subsequent 12 bytes encode the term length, as denominated in
        // the encoded amortization unit.
        bytes32 termLengthInAmortizationUnitsShifted = parameters & 0x000000000000000000000000000000000ffffffffffffffffffffffff0000000;

        bytes32 gracePeriodInDaysShifted = parameters & 0x000000000000000000000000000000000000000000000000000000000ff00000;

        return (
            _bitShiftRight(principalTokenIndexShifted, 248),
            _bitShiftRight(principalAmountShifted, 152),
            _bitShiftRight(interestRateShifted, 128),
            _bitShiftRight(amortizationUnitTypeShifted, 124),
            _bitShiftRight(termLengthInAmortizationUnitsShifted, 28),
            _bitShiftRight(gracePeriodInDaysShifted, 20)
        );
    }

    /**
    *
    */
    function _validateNewCollateralParamsSecureLoan(
        bytes16 _oldCollateralParams,
        bytes16 _newCollateralParams,
        uint _additionAmount
    ) internal pure returns (bool) {
        bool isCollateralTokenIndexCorrect = _bitShiftRight16(_oldCollateralParams & 0xff000000000000000000000000000000, 120)
            == _bitShiftRight16(_newCollateralParams & 0xff000000000000000000000000000000, 120);

        bool isValidAmount = _bitShiftRight16(_newCollateralParams & 0x00ffffffffffffffffffffffff000000, 24)
            .sub(_bitShiftRight16(_oldCollateralParams & 0x00ffffffffffffffffffffffff000000, 24)) == _additionAmount;

        return (
            isCollateralTokenIndexCorrect &&
            isValidAmount
        );

    }

    function _validateNewCollateralParamsSellCollateral(
        bytes16 _oldCollateralParams,
        bytes16 _newCollateralParams,
        uint _sellAmount
    ) internal pure returns (bool) {
        bool isCollateralTokenIdCorrect = _bitShiftRight16(_oldCollateralParams & 0xff000000000000000000000000000000, 120)
            == _bitShiftRight16(_newCollateralParams & 0xff000000000000000000000000000000, 120);

        bool isValidAmount = _bitShiftRight16(_oldCollateralParams & 0x00ffffffffffffffffffffffff000000, 24)
            .sub(_bitShiftRight16(_newCollateralParams & 0x00ffffffffffffffffffffffff000000, 24)) == _sellAmount;

        return (
            isCollateralTokenIdCorrect &&
            isValidAmount
        );

    }

    function _validateNewInventoryCollateralParamsSecureLoan(
        bytes16 _oldCollateralParams,
        bytes16 _newCollateralParams,
        uint _additionAmount
    ) internal pure returns (bool) {
        bool isCollateralTokenIdCorrect = _bitShiftRight16(_oldCollateralParams & 0xffffffff000000000000000000000000, 96)
            == _bitShiftRight16(_newCollateralParams & 0xffffffff000000000000000000000000, 96);

        bool isValidAmount = _bitShiftRight16(_newCollateralParams & 0x00000000ffffffffffffffffffffffff, 0)
            .sub(_bitShiftRight16(_oldCollateralParams & 0x00000000ffffffffffffffffffffffff, 0)) == _additionAmount;

        return (
            isCollateralTokenIdCorrect &&
            isValidAmount
        );

    }

    function _validateNewInventoryCollateralParamsSellCollateral(
        bytes16 _oldCollateralParams,
        bytes16 _newCollateralParams,
        uint _sellAmount
    ) internal pure returns (bool) {
        bool isCollateralTokenIdCorrect = _bitShiftRight16(_oldCollateralParams & 0xffffffff000000000000000000000000, 96)
            == _bitShiftRight16(_newCollateralParams & 0xffffffff000000000000000000000000, 96);

        bool isValidAmount = _bitShiftRight16(_oldCollateralParams & 0x00000000ffffffffffffffffffffffff, 0)
            .sub(_bitShiftRight16(_newCollateralParams & 0x00000000ffffffffffffffffffffffff, 0)) == _sellAmount;

        return (
            isCollateralTokenIdCorrect &&
            isValidAmount
        );

    }

    /**
    *
    */
    function _validateNewInventoryTermsContractParamsDrawdown(
        bytes32 _oldTermsContractParameters,
        bytes32 _newTermsContractParameters,
        uint _drawdownAmount
    ) internal pure returns (bool) {
        bool isPrincipalTokenIndexCorrect = _bitShiftRight(_oldTermsContractParameters & 0xff00000000000000000000000000000000000000000000000000000000000000, 248)
            == _bitShiftRight(_newTermsContractParameters & 0xff00000000000000000000000000000000000000000000000000000000000000, 248);

        bool isValidPrincipalAmount = _bitShiftRight(_newTermsContractParameters & 0x00ffffffffffffffffffffffff00000000000000000000000000000000000000, 152)
            .sub(_bitShiftRight(_oldTermsContractParameters & 0x00ffffffffffffffffffffffff00000000000000000000000000000000000000, 152)) == _drawdownAmount;

        bool isInterestRateCorrect = _bitShiftRight(_oldTermsContractParameters & 0x00000000000000000000000000ffffff00000000000000000000000000000000, 128)
            == _bitShiftRight(_newTermsContractParameters & 0x00000000000000000000000000ffffff00000000000000000000000000000000, 128);

        bool isAmortizationUnitTypeCorrect = _bitShiftRight(_oldTermsContractParameters & 0x00000000000000000000000000000000f0000000000000000000000000000000, 124)
            == _bitShiftRight(_newTermsContractParameters & 0x00000000000000000000000000000000f0000000000000000000000000000000, 124);

        bool isTermLengthInAmortizationUnitsCorrect = _bitShiftRight(_oldTermsContractParameters & 0x000000000000000000000000000000000ffffffffffffffffffffffff0000000, 28)
            == _bitShiftRight(_newTermsContractParameters & 0x000000000000000000000000000000000ffffffffffffffffffffffff0000000, 28);

        bool isGracePeriodInDaysCorrect = _bitShiftRight(_oldTermsContractParameters & 0x000000000000000000000000000000000000000000000000000000000ff00000, 20)
            == _bitShiftRight(_newTermsContractParameters & 0x000000000000000000000000000000000000000000000000000000000ff00000, 20);

        return (
            isPrincipalTokenIndexCorrect &&
            isValidPrincipalAmount &&
            isInterestRateCorrect &&
            isAmortizationUnitTypeCorrect &&
            isTermLengthInAmortizationUnitsCorrect &&
            isGracePeriodInDaysCorrect
        );

    }

    function _validateNewTermsContractParamsDrawdown(
        bytes32 _oldTermsContractParameters,
        bytes32 _newTermsContractParameters,
        uint _drawdownAmount
    ) internal pure returns (bool) {
        bool isPrincipalTokenIndexCorrect = _bitShiftRight(_oldTermsContractParameters & 0xff00000000000000000000000000000000000000000000000000000000000000, 248)
            == _bitShiftRight(_newTermsContractParameters & 0xff00000000000000000000000000000000000000000000000000000000000000, 248);

        bool isValidPrincipalAmount = _bitShiftRight(_newTermsContractParameters & 0x00ffffffffffffffffffffffff00000000000000000000000000000000000000, 152)
            .sub(_bitShiftRight(_oldTermsContractParameters & 0x00ffffffffffffffffffffffff00000000000000000000000000000000000000, 152)) == _drawdownAmount;

        bool isInterestRateCorrect = _bitShiftRight(_oldTermsContractParameters & 0x00000000000000000000000000ffffff00000000000000000000000000000000, 128)
            == _bitShiftRight(_newTermsContractParameters & 0x00000000000000000000000000ffffff00000000000000000000000000000000, 128);

        bool isAmortizationUnitTypeCorrect = _bitShiftRight(_oldTermsContractParameters & 0x00000000000000000000000000000000f0000000000000000000000000000000, 124)
            == _bitShiftRight(_newTermsContractParameters & 0x00000000000000000000000000000000f0000000000000000000000000000000, 124);

        bool isTermLengthInAmortizationUnitsCorrect = _bitShiftRight(_oldTermsContractParameters & 0x000000000000000000000000000000000ffffffffffffffffffffffff0000000, 28)
            == _bitShiftRight(_newTermsContractParameters & 0x000000000000000000000000000000000ffffffffffffffffffffffff0000000, 28);

        bool isGracePeriodInDaysCorrect = _bitShiftRight(_oldTermsContractParameters & 0x000000000000000000000000000000000000000000000000000000000ff00000, 20)
            == _bitShiftRight(_newTermsContractParameters & 0x000000000000000000000000000000000000000000000000000000000ff00000, 20);

        return (
            isPrincipalTokenIndexCorrect &&
            isValidPrincipalAmount &&
            isInterestRateCorrect &&
            isAmortizationUnitTypeCorrect &&
            isTermLengthInAmortizationUnitsCorrect &&
            isGracePeriodInDaysCorrect
        );

    }

    /**
    * Unpack data from hex string which including informations about Loan
    */
    function unpackParametersFromBytes(bytes32 parameters)
        public
        pure
        returns (
            uint _principalTokenIndex,
            uint _principalAmount,
            uint _interestRate,
            uint _amortizationUnitType,
            uint _termLengthInAmortizationUnits,
            uint _gracePeriodInDays
        )
    {
        return _unpackLoanTermsParametersFromBytes(parameters);
    }
}
