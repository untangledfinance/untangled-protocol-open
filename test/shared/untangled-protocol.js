const { utils } = require('ethers');
const { ethers } = require('hardhat');
const { getChainId } = require('hardhat');
const { BigNumber } = ethers;
const { parseEther, formatEther } = ethers.utils;
const { RATE_SCALING_FACTOR } = require('../shared/constants.js');

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
const { SaleType } = require('./constants');
const { expect } = require('chai');
const { presignedMintMessage } = require('./uid-helper.js');

function getTokenAddressFromSymbol(symbol) {
    switch (symbol) {
        case 'cUSD':
            return this.stableCoin.address;
        case 'USDT':
            return this.stableCoin.address;
        case 'USDC':
            return this.stableCoin.address;
    }
}

async function createSecuritizationPool(
    signer,
    minFirstLossCushion = 10,
    debtCeiling = 1000,
    currency = "cUSD",
    validatorRequired = true,
    salt = utils.keccak256(Date.now())
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
                        currency: getTokenAddressFromSymbol.call(this, currency),
                        minFirstLossCushion: BigNumber.from(minFirstLossCushion * RATE_SCALING_FACTOR),
                        validatorRequired: validatorRequired,
                        debtCeiling: parseEther(debtCeiling.toString()).toString(),
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

async function fillDebtOrder(
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


    const fillDebtOrderParams = formatFillDebtOrderParams(
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
                    this.defaultLoanAssetTokenValidator.address
                )),
            }))
        )
    );
    await this.loanKernel.connect(signer).fillDebtOrder(fillDebtOrderParams);
    return tokenIds;
}

async function initSOTSale(signer, saleParameters) {

    const transactionSOTSale = await this.securitizationManager.connect(signer).setUpTGEForSOT(
        {
            issuerTokenController: saleParameters.issuerTokenController,
            pool: saleParameters.pool,
            minBidAmount: saleParameters.minBidAmount,
            saleType: saleParameters.saleType,
            longSale: true,
            ticker: saleParameters.ticker,
        },
        { openingTime: saleParameters.openingTime, closingTime: saleParameters.closingTime, rate: saleParameters.rate, cap: saleParameters.cap },
        {
            initialInterest: saleParameters.initialInterest,
            finalInterest: saleParameters.finalInterest,
            timeInterval: saleParameters.timeInterval,
            amountChangeEachInterval: saleParameters.amountChangeEachInterval,
        }
    );
    const receiptSOTSale = await transactionSOTSale.wait();
    const [sotTGEAddress] = receiptSOTSale.events.find((e) => e.event == 'NewTGECreated').args;
    const [sotTokenAddress] = receiptSOTSale.events.find((e) => e.event == 'NewNotesTokenCreated').args;

    return { sotTGEAddress, sotTokenAddress };
}

async function initJOTSale(signer, saleParameters) {
    const transactionJOTSale = await this.securitizationManager.connect(signer).setUpTGEForJOT(
        {
            issuerTokenController: saleParameters.issuerTokenController,
            pool: saleParameters.pool,
            minBidAmount: saleParameters.minBidAmount,
            saleType: saleParameters.saleType,
            longSale: true,
            ticker: saleParameters.ticker,
        },
        { openingTime: saleParameters.openingTime, closingTime: saleParameters.closingTime, rate: saleParameters.rate, cap: saleParameters.cap },
        saleParameters.initialJOTAmount
    );
    const receiptJOTSale = await transactionJOTSale.wait();
    const [jotTGEAddress] = receiptJOTSale.events.find((e) => e.event == 'NewTGECreated').args;
    const [jotTokenAddress] = receiptJOTSale.events.find((e) => e.event == 'NewNotesTokenCreated').args;

    return { jotTGEAddress, jotTokenAddress };

}

async function buySOT(signer, sotTGEAddress, currencyAmount) {
    await this.stableCoin.connect(signer).approve(sotTGEAddress, currencyAmount);
    return this.securitizationManager.connect(signer).buyTokens(sotTGEAddress, currencyAmount);
}

async function buyJOT(signer, jotTGEAddress, currencyAmount) {
    await this.stableCoin.connect(signer).approve(jotTGEAddress, currencyAmount);
    return this.securitizationManager.connect(signer).buyTokens(jotTGEAddress, currencyAmount);
}

/**
 * Generates a unique identifier to signer.
 * @param  signer - The signer that signed transaction and received the unique identifier.
 */
async function mintUID (signer) {
    const UID_TYPE = 0;
    const chainId = await getChainId();
    const expiredAt = dayjs().unix() + 86400 * 1000;
    const nonce = 0;
    const ethRequired = parseEther('0.00083');

    const uidMintMessage = presignedMintMessage(
      signer.address,
      UID_TYPE,
      expiredAt,
      this.uniqueIdentity.address,
      nonce,
      chainId
    );
    const signature = await this.untangledAdminSigner.signMessage(uidMintMessage);
    await this.uniqueIdentity.connect(signer).mint(UID_TYPE, expiredAt, signature, { value: ethRequired });

}
function bind(contracts) {
    return {
        createSecuritizationPool: createSecuritizationPool.bind(contracts),
        setupRiskScore: setupRiskScore.bind(contracts),
        uploadLoans: fillDebtOrder.bind(contracts),
        initSOTSale: initSOTSale.bind(contracts),
        initJOTSale: initJOTSale.bind(contracts),
        buySOT: buySOT.bind(contracts),
        buyJOT: buyJOT.bind(contracts),
        mintUID: mintUID.bind(contracts),
    }
}

module.exports.bind = bind;
