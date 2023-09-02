const { ethers, utils } = require('ethers');
const { BigNumber } = require('bignumber.js');

const unlimitedAllowance = '115792089237316195423570985008687907853269984665640564039457584007913129639935';

function saltFromOrderValues(orderValues, length) {
  const salts = [];

  for (let i = 2 + length * 2; i < 2 + length * 3; i++) {
    salts[i - 2 - length * 2] = orderValues[i];
  }
  return salts;
}

function debtorsFromOrderAddresses(orderAddresses, length) {
  const debtors = [];
  for (let i = 5; i < 5 + length; i++) {
    debtors[i - 5] = orderAddresses[i];
  }
  return debtors;
}

function genLoanAgreementIds(version, debtors, termsContract, termsContractParameters, salts) {
  const agreementIds = [];
  for (let i = 0; i < 0 + salts.length; i++) {
    agreementIds[i] = utils.keccak256(
      ethers.utils.solidityPack(
        ['address', 'address', 'address', 'bytes32', 'uint256'],
        [version, debtors[i], termsContract, termsContractParameters[i], salts[i]]
      )
    );
  }
  return agreementIds;
}

const bitShiftLeft = (target, numPlaces) => {
  const binaryTargetString = target.toString(2);
  const binaryTargetStringShifted = binaryTargetString + '0'.repeat(numPlaces);
  return new BigNumber(binaryTargetStringShifted, 2);
};

const packTermsContractParameters = ({
  principalAmount,
  amortizationUnitType,
  termLengthUnits,
  gracePeriodInDays,
  interestRateFixedPoint,
}) => {
  const principalAmountShifted = bitShiftLeft(principalAmount, 152);
  const interestRateShifted = bitShiftLeft(interestRateFixedPoint, 128);
  const amortizationUnitTypeShifted = bitShiftLeft(amortizationUnitType, 124);
  const termLengthShifted = bitShiftLeft(termLengthUnits, 28);
  const gracePeriodInDaysShifted = bitShiftLeft(gracePeriodInDays, 20);
  const baseTenParameters = new BigNumber('0')
    .plus(new BigNumber(principalAmountShifted))
    .plus(new BigNumber(interestRateShifted))
    .plus(new BigNumber(amortizationUnitTypeShifted))
    .plus(new BigNumber(termLengthShifted))
    .plus(new BigNumber(gracePeriodInDaysShifted));

  let result = `0x${baseTenParameters.toString(16).padStart(64, '0')}`;
  return result;
};

const INTEREST_RATE_SCALING_FACTOR = new BigNumber(10 ** 4);
const interestRateFixedPoint = (amount) => {
  return new BigNumber(amount).times(INTEREST_RATE_SCALING_FACTOR);
};

module.exports = {
  unlimitedAllowance,
  saltFromOrderValues,
  debtorsFromOrderAddresses,
  genLoanAgreementIds,
  packTermsContractParameters,
  interestRateFixedPoint,
};
