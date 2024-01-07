const { utils } = require('ethers');
const { ethers } = require('hardhat');
const { parseEther, formatEther } = ethers.utils;

const {
    unlimitedAllowance,
    genLoanAgreementIds,
    saltFromOrderValues,
    debtorsFromOrderAddresses,
    packTermsContractParameters,
    interestRateFixedPoint,
    genSalt,
    generateLATMintPayload,
    genRiskScoreParam,
    getPoolByAddress,
    getPoolAbi,
    formatFillDebtOrderParams,
    ZERO_ADDRESS,
} = require('../utils.js');
const dayjs = require('dayjs');
const _ = require('lodash');

async function createSecuritizationPool(
    signer,
    minFirstLossCushion = '100000',
    debtCeiling = parseEther('1000').toString(),
    currency = this.stableCoin.address,
    salt = utils.keccak256(Date.now()),
    validatorRequired = true
) {

    let transaction = await this.securitizationManager
        .connect(signer)

        .newPoolInstance(
            salt,

            signer.address,
            utils.defaultAbiCoder.encode(
                [
                    {
                        type: 'tuple',
                        components: [
                            {
                                name: 'currency',
                                type: 'address',
                            },
                            {
                                name: 'minFirstLossCushion',
                                type: 'uint32',
                            },
                            {
                                name: 'validatorRequired',
                                type: 'bool',
                            },
                            {
                                name: 'debtCeiling',
                                type: 'uint256',
                            },
                        ],
                    },
                ],
                [
                    {
                        currency: currency,
                        minFirstLossCushion: minFirstLossCushion,
                        validatorRequired: validatorRequired,
                        debtCeiling: debtCeiling,
                    },
                ]
            )
        );

    return transaction.wait();
}

async function setupRiskScore(
    signer,
    securitizationPoolContract,
    riskScores,
) {

    const { daysPastDues, ratesAndDefaults, periodsAndWriteOffs } = genRiskScoreParam(
        ...riskScores
    );

    return securitizationPoolContract
        .connect(signer)
        .setupRiskScores(daysPastDues, ratesAndDefaults, periodsAndWriteOffs);
}

async function getFillDebtOrderParameters(
    signer,
    securitizationPoolContract,
    relayer,
    borrowerSigner,
    assetPurpose,
    loans,
) {
    const CREDITOR_FEE = '0';

    const orderAddresses = [
        securitizationPoolContract.address,
        this.stableCoin.address,
        this.loanRepaymentRouter.address,
        relayer.address,
        // borrower 1
        // borrower 2
        // ...
        ...new Array(loans.length).fill(borrowerSigner.address)
    ];

    const orderValues = [
        CREDITOR_FEE,
        assetPurpose,
        ...loans.map(l => parseEther(l.principalAmount.toString())),
        ...loans.map(l => l.expirationTimestamp),
        ...loans.map(l => l.salt || genSalt()),
        ...loans.map(l => l.riskScore)
    ];

    const interestRatePercentage = 5;

    const termsContractParameters = loans.map(l => packTermsContractParameters({
        amortizationUnitType: 1,
        gracePeriodInDays: 2,
        principalAmount: l.principalAmount,
        termLengthUnits: _.ceil(l.termInDays * 24),
        interestRateFixedPoint: interestRateFixedPoint(interestRatePercentage)

    }));

    const salts = saltFromOrderValues(orderValues, termsContractParameters.length);
    const debtors = debtorsFromOrderAddresses(orderAddresses, termsContractParameters.length);

    const tokenIds = genLoanAgreementIds(this.loanRepaymentRouter.address, debtors, termsContractParameters, salts);


    return {
       fillDebtOrderParams: formatFillDebtOrderParams(
           orderAddresses,
           orderValues,
           termsContractParameters,
           await Promise.all(
               tokenIds.map(async (x) => ({
                   ...(await generateLATMintPayload(
                       this.loanAssetTokenContract,
                       this.defaultLoanAssetTokenValidator,
                       [x],
                       [(await this.loanAssetTokenContract.nonce(x)).toNumber()],
                       this.defaultLoanAssetTokenValidator.address,
                   )),
               })),
           ),
       ),
       tokenIds
    }

}

function bind(contracts) {
    return {
        createSecuritizationPool: createSecuritizationPool.bind(contracts),
        setupRiskScore: setupRiskScore.bind(contracts),
        getFillDebtOrderParameters: getFillDebtOrderParameters.bind(contracts)
    }
}

module.exports.bind = bind;
