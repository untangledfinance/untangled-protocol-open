const { ethers, utils } = require('ethers');

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

module.exports = {
  unlimitedAllowance,
  saltFromOrderValues,
  debtorsFromOrderAddresses,
  genLoanAgreementIds,
};
