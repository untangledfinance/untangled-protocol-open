const { ethers, artifacts } = require('hardhat');
const { utils, Contract } = require('ethers');

const { BigNumber } = require('bignumber.js');
const crypto = require('crypto');

const unlimitedAllowance = '115792089237316195423570985008687907853269984665640564039457584007913129639935';
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

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

const genSalt = () => {
  const saltBuffer = crypto.randomBytes(8);
  const saltBufferHex = saltBuffer.toString('hex');
  return new BigNumber(`0x${saltBufferHex}`).toString();
};

const generateEntryHash = (payer, receiver, fiatAmount, dueDate, salt) => {
  return utils.keccak256(
    ethers.utils.solidityPack(
      ['address', 'address', 'uint256', 'uint256', 'uint256'],
      [payer, receiver, fiatAmount, dueDate, salt]
    )
  );
};


const generateLATMintPayload = async (loanAssetToken, signer, tokenIds, nonces, validator) => {
  await signer.provider.ready;

  const network = await signer.provider.getNetwork();

  const domain = {
    name: 'UntangledLoanAssetToken',
    version: '0.0.1',
    chainId: network.chainId,
    verifyingContract: loanAssetToken.address,
  }

  const message = {
    tokenIds,
    nonces,
    validator,
  };

  const validateSignature = await signer._signTypedData(
    domain,
    {
      LoanAssetToken: [
        {
          name: "tokenIds",
          type: "uint256[]"
        },
        {
          name: "nonces",
          type: "uint256[]"
        },
        {
          name: "validator",
          type: "address"
        }
      ],
    },
    message,
  )

  // const add = require('@metamask/eth-sig-util').recoverTypedSignature({
  //   data: {
  //     domain,
  //     types: {
  //       EIP712Domain: [
  //         {
  //           name: "name",
  //           type: "string",
  //         },
  //         {
  //           name: "version",
  //           type: "string",
  //         },
  //         {
  //           name: "chainId",
  //           type: "uint256",
  //         },
  //         {
  //           name: "verifyingContract",
  //           type: "address",
  //         },
  //       ],
  //       LoanAssetToken: [
  //         {
  //           name: "tokenIds",
  //           type: "uint256[]"
  //         },
  //         {
  //           name: "nonces",
  //           type: "uint256[]"
  //         },
  //         {
  //           name: "validator",
  //           type: "address"
  //         }
  //       ],
  //     },
  //     message,
  //     primaryType: 'LoanAssetToken',
  //   }, signature: validateSignature, version: 'V4'
  // })

  return {
    validateSignature,
    tokenIds,
    nonces,
    validator,
  };
}

const getPoolAbi = async () => {
  const asset = await artifacts.readArtifact('ISecuritizationPool');
  const control = await artifacts.readArtifact('SecuritizationAccessControl');
  const distribution = await artifacts.readArtifact('SecuritizationLockDistribution');
  const storage = await artifacts.readArtifact('SecuritizationPoolStorage');
  const tge = await artifacts.readArtifact('SecuritizationTGE');

  const abis = [
    ...storage.abi,
    ...asset.abi,
    ...control.abi,
    ...distribution.abi,
    ...tge.abi,
  ];

  const resultAbis = [];
  // remove duplicate
  for (const abi of abis) {
    if (resultAbis.find(x => x.name == abi.name)) {
      continue;
    }

    resultAbis.push(abi);
  }

  return resultAbis;
}


const getPoolByAddress = async (address) => {
  const asset = await artifacts.readArtifact('ISecuritizationPool');
  const control = await artifacts.readArtifact('SecuritizationAccessControl');
  const distribution = await artifacts.readArtifact('SecuritizationLockDistribution');
  const storage = await artifacts.readArtifact('SecuritizationPoolStorage');
  const tge = await artifacts.readArtifact('SecuritizationTGE');

  const abis = await getPoolAbi();

  const provider = ethers.provider;
  return new Contract(address, abis, provider);
}

module.exports = {
  unlimitedAllowance,
  ZERO_ADDRESS,
  saltFromOrderValues,
  debtorsFromOrderAddresses,
  genLoanAgreementIds,
  packTermsContractParameters,
  interestRateFixedPoint,
  genSalt,
  bitShiftLeft,
  generateEntryHash,

  generateLATMintPayload,
  getPoolByAddress,
  getPoolAbi,
};
