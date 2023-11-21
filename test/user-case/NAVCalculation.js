const { ethers } = require('hardhat');
const { expect } = require('chai');
const { BigNumber, utils } = require('ethers');
const {
  genSalt,
  packTermsContractParameters,
  interestRateFixedPoint,
  saltFromOrderValues,
  debtorsFromOrderAddresses,
  genLoanAgreementIds, unlimitedAllowance,
  generateLATMintPayload
} = require('../utils');
const { parseEther, parseUnits, formatEther, formatBytes32String } = ethers.utils;
const dayjs = require('dayjs');
const _ = require('lodash');
const { time, impersonateAccount, stopImpersonatingAccount, setBalance } = require('@nomicfoundation/hardhat-network-helpers');
const { POOL_ADMIN_ROLE } = require('../constants.js');
const { parse } = require('dotenv');
const { setup } = require('../setup');

const ONE_DAY = 86400;

const YEAR_LENGTH_IN_SECONDS = 31536000; // Number of seconds in a year (approximately)
function calculateInterestForDuration(principalAmount, interestRate, durationLengthInSec) {
  // Calculate the interest rate as a fraction
  const interestRateFraction = (interestRate * (1 / 100));

  // Calculate the compound interest using the formula
  const compoundInterest = principalAmount *
    Math.pow(
      1 + interestRateFraction / YEAR_LENGTH_IN_SECONDS,
      durationLengthInSec
    ) -
    principalAmount;

  return compoundInterest;
}
describe('NAVCalculation', () => {
  let stableCoin;
  let securitizationManager;
  let loanKernel;
  let loanRepaymentRouter;
  let loanAssetTokenContract;
  let loanRegistry;
  let uniqueIdentity;
  let registry;
  let loanInterestTermsContract;
  let distributionOperator;
  let distributionTranche;
  let securitizationPoolContract;
  let securitizationPoolValueService;
  let tokenIds;
  let defaultLoanAssetTokenValidator;
  let poolNAV;

  // Wallets
  let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer,
    impersonationKernel;

  before('create fixture', async () => {
    [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer, impersonationKernel] =
      await ethers.getSigners();

    ({
      stableCoin,
      distributionOperator,
      distributionTranche,
      securitizationPoolValueService,
      uniqueIdentity,
      loanAssetTokenContract,
      loanInterestTermsContract,
      loanRegistry,
      loanKernel,
      loanRepaymentRouter,
      securitizationManager,
      distributionOperator,
      distributionTranche,
      registry,
      defaultLoanAssetTokenValidator,
    } = await setup());

    const OWNER_ROLE = await securitizationManager.OWNER_ROLE();
    await securitizationManager.setRoleAdmin(POOL_ADMIN_ROLE, OWNER_ROLE);

    await securitizationManager.grantRole(OWNER_ROLE, borrowerSigner.address);
    await securitizationManager.connect(borrowerSigner).grantRole(POOL_ADMIN_ROLE, poolCreatorSigner.address);
    // Create new pool
    const transaction = await securitizationManager
      .connect(poolCreatorSigner)
      .newPoolInstance(
            utils.keccak256(Date.now()),

            poolCreatorSigner.address,
            utils.defaultAbiCoder.encode([
              {
                type: 'tuple',
                components: [
                  {
                    name: 'currency',
                    type: 'address'
                  },
                  {
                    name: 'minFirstLossCushion',
                    type: 'uint32'
                  },
                  {
                    name: "validatorRequired",
                    type: "bool"
                  }
                ]
              }
            ], [
              {
                currency: stableCoin.address,
                minFirstLossCushion: '100000',
                validatorRequired: true
              }
            ]));
    const receipt = await transaction.wait();
    const [securitizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;

    securitizationPoolContract = await ethers.getContractAt('SecuritizationPool', securitizationPoolAddress);
  });

  const agreementID = '0x979b5e9fab60f9433bf1aa924d2d09636ae0f5c10e2c6a8a58fe441cd1414d7f';
  let expirationTimestamps;
  const CREDITOR_FEE = '0';
  const ASSET_PURPOSE = '1';
  const inputAmount = 10;
  const inputPrice = 15;
  const principalAmount = 10000000000000000000;
  const interestRatePercentage = 12; //12%
  describe('#getExpectedRepaymentValues', () => {
    before('upload a loan', async () => {
      // Setup Risk Scores
      const ONE_DAY_IN_SECONDS = 86400;

      // A
      const riskScoreA = {
        daysPastDue: ONE_DAY_IN_SECONDS,
        advanceRate: 950000, // 95%
        penaltyRate: 900000,
        interestRate: 80000, // 8%
        probabilityOfDefault: 10000, // 1%
        lossGivenDefault: 810000, // 25%
        discountRate: 100000, // 10%
        gracePeriod: ONE_DAY_IN_SECONDS*5,
        collectionPeriod: ONE_DAY_IN_SECONDS*30,
        writeOffAfterGracePeriod: 250000, // 25%
        writeOffAfterCollectionPeriod: 1000000, // 100%
      };
      // B
      const riskScoreB = {
        daysPastDue: ONE_DAY_IN_SECONDS * 30,
        advanceRate: 900000, // 90%
        penaltyRate: 1500000,
        interestRate: 100000, // 10%
        probabilityOfDefault: 20000, // 2%
        lossGivenDefault: 500000, // 50%
        discountRate: 100000, // 10%
        gracePeriod: ONE_DAY_IN_SECONDS*5,
        collectionPeriod: ONE_DAY_IN_SECONDS*30,
        writeOffAfterGracePeriod: 500000, // 50%
        writeOffAfterCollectionPeriod: 1000000, // 100%
      };
      // C
      const riskScoreC = {
        daysPastDue: ONE_DAY_IN_SECONDS * 60,
        advanceRate: 900000, // 90%
        penaltyRate: 1500000,
        interestRate: 120000, // 12%
        probabilityOfDefault: 30000, // 3%
        lossGivenDefault: 500000, // 50%
        discountRate: 100000, // 10%
        gracePeriod: ONE_DAY_IN_SECONDS * 5,
        collectionPeriod: ONE_DAY_IN_SECONDS * 30,
        writeOffAfterGracePeriod: 500000, // 50%
        writeOffAfterCollectionPeriod: 1000000, // 100%
      };
      // D
      const riskScoreD = {
        daysPastDue: ONE_DAY_IN_SECONDS * 90,
        advanceRate: 800000, // 80%
        penaltyRate: 1500000,
        interestRate: 120000, // 12%
        probabilityOfDefault: 40000, // 3%
        lossGivenDefault: 750000, // 50%
        discountRate: 100000, // 10%
        gracePeriod: ONE_DAY_IN_SECONDS * 5,
        collectionPeriod: ONE_DAY_IN_SECONDS * 30,
        writeOffAfterGracePeriod: 500000, // 50%
        writeOffAfterCollectionPeriod: 1000000, // 100%
      };
      // E
      const riskScoreE = {
        daysPastDue: ONE_DAY_IN_SECONDS * 120,
        advanceRate: 800000, // 80%
        penaltyRate: 1500000,
        interestRate: 140000, // 12%
        probabilityOfDefault: 50000, // 3%
        lossGivenDefault: 1000000, // 50%
        discountRate: 100000, // 10%
        gracePeriod: ONE_DAY_IN_SECONDS * 5,
        collectionPeriod: ONE_DAY_IN_SECONDS * 30,
        writeOffAfterGracePeriod: 1000000, // 100%
        writeOffAfterCollectionPeriod: 1000000, // 100%
      };

      // F
      const riskScoreF = {
        daysPastDue: ONE_DAY_IN_SECONDS * 365,
        advanceRate: 0, // 0%
        penaltyRate: 1500000,
        interestRate: 100000, // 100%
        probabilityOfDefault: 100000, // 100%
        lossGivenDefault: 1000000, // 100%
        discountRate: 100000, // 10%
        gracePeriod: ONE_DAY_IN_SECONDS * 5,
        collectionPeriod: ONE_DAY_IN_SECONDS * 30,
        writeOffAfterGracePeriod: 1000000, // 100%
        writeOffAfterCollectionPeriod: 1000000, // 100%
      };
      const daysPastDues = [
        riskScoreA.daysPastDue,
        riskScoreB.daysPastDue,
        riskScoreC.daysPastDue,
        riskScoreD.daysPastDue,
        riskScoreE.daysPastDue,
        riskScoreF.daysPastDue
      ];

      const ratesAndDefaults = [
        riskScoreA.advanceRate,
        riskScoreB.advanceRate,
        riskScoreC.advanceRate,
        riskScoreD.advanceRate,
        riskScoreE.advanceRate,
        riskScoreF.advanceRate,
        riskScoreA.penaltyRate,
        riskScoreB.penaltyRate,
        riskScoreC.penaltyRate,
        riskScoreD.penaltyRate,
        riskScoreF.penaltyRate,
        riskScoreE.penaltyRate,
        riskScoreA.interestRate,
        riskScoreB.interestRate,
        riskScoreC.interestRate,
        riskScoreD.interestRate,
        riskScoreE.interestRate,
        riskScoreF.interestRate,
        riskScoreA.probabilityOfDefault,
        riskScoreB.probabilityOfDefault,
        riskScoreC.probabilityOfDefault,
        riskScoreD.probabilityOfDefault,
        riskScoreE.probabilityOfDefault,
        riskScoreF.probabilityOfDefault,
        riskScoreA.lossGivenDefault,
        riskScoreB.lossGivenDefault,
        riskScoreC.lossGivenDefault,
        riskScoreD.lossGivenDefault,
        riskScoreE.lossGivenDefault,
        riskScoreF.lossGivenDefault,
        riskScoreA.discountRate,
        riskScoreB.discountRate,
        riskScoreC.discountRate,
        riskScoreD.discountRate,
        riskScoreE.discountRate,
        riskScoreF.discountRate
      ];
      const periodsAndWriteOffs = [
        riskScoreA.gracePeriod,
        riskScoreB.gracePeriod,
        riskScoreC.gracePeriod,
        riskScoreD.gracePeriod,
        riskScoreE.gracePeriod,
        riskScoreF.gracePeriod,
        riskScoreA.collectionPeriod,
        riskScoreB.collectionPeriod,
        riskScoreC.collectionPeriod,
        riskScoreD.collectionPeriod,
        riskScoreE.collectionPeriod,
        riskScoreF.collectionPeriod,
        riskScoreA.writeOffAfterGracePeriod,
        riskScoreB.writeOffAfterGracePeriod,
        riskScoreC.writeOffAfterGracePeriod,
        riskScoreD.writeOffAfterGracePeriod,
        riskScoreE.writeOffAfterGracePeriod,
        riskScoreF.writeOffAfterGracePeriod,
        riskScoreA.writeOffAfterCollectionPeriod,
        riskScoreB.writeOffAfterCollectionPeriod,
        riskScoreC.writeOffAfterCollectionPeriod,
        riskScoreD.writeOffAfterCollectionPeriod,
        riskScoreE.writeOffAfterCollectionPeriod,
        riskScoreF.writeOffAfterCollectionPeriod
      ];

      await securitizationPoolContract
        .connect(poolCreatorSigner)
        .setupRiskScores(daysPastDues, ratesAndDefaults, periodsAndWriteOffs);

      // Grant role originator
      const ORIGINATOR_ROLE = await securitizationPoolContract.ORIGINATOR_ROLE();
      await securitizationPoolContract.connect(poolCreatorSigner).grantRole(ORIGINATOR_ROLE, originatorSigner.address)

      // Prepare parameters for loan upload
      const orderAddresses = [
        originatorSigner.address,
        stableCoin.address,
        loanRepaymentRouter.address,
        loanInterestTermsContract.address,
        relayer.address,
        borrowerSigner.address,
      ];

      const salt = genSalt();
      const riskScore = '3';
      expirationTimestamps = await time.latest() + 30 * ONE_DAY_IN_SECONDS;

      const orderValues = [
        CREDITOR_FEE,
        ASSET_PURPOSE,
        principalAmount.toString(),
        expirationTimestamps,
        salt,
        riskScore,
      ];

      const termInDaysLoan = 30;
      const termsContractParameter = packTermsContractParameters({
        amortizationUnitType: 1,
        gracePeriodInDays: 5,
        principalAmount: principalAmount,
        termLengthUnits: _.ceil(termInDaysLoan * 24),
        interestRateFixedPoint: interestRateFixedPoint(interestRatePercentage),
      });

      const termsContractParameters = [termsContractParameter];

      const salts = saltFromOrderValues(orderValues, termsContractParameters.length);
      const debtors = debtorsFromOrderAddresses(orderAddresses, termsContractParameters.length);

      tokenIds = genLoanAgreementIds(
        loanRepaymentRouter.address,
        debtors,
        loanInterestTermsContract.address,
        termsContractParameters,
        salts
      );

      // Upload, tokenize loan assets
      await loanKernel.fillDebtOrder(
          orderAddresses,
          orderValues,
          termsContractParameters,
          await Promise.all(
              tokenIds.map(async (x) => ({
                  ...(await generateLATMintPayload(
                      loanAssetTokenContract,
                      defaultLoanAssetTokenValidator,
                      [x],
                      [(await loanAssetTokenContract.nonce(x)).toNumber()],
                      defaultLoanAssetTokenValidator.address
                  )),
              }))
          )
      );

      // Transfer LAT asset to pool
      await loanAssetTokenContract.connect(originatorSigner).setApprovalForAll(securitizationPoolContract.address, true);
      await securitizationPoolContract.connect(originatorSigner)
        .collectAssets(loanAssetTokenContract.address, originatorSigner.address, tokenIds);

      // PoolNAV contract
      const poolNAVAddress = await securitizationPoolContract.poolNAV();
      poolNAV = await ethers.getContractAt('PoolNAV', poolNAVAddress);
    });

    it('after upload loan successfully', async () => {
      const currentNAV = await poolNAV.currentNAV();

      const debtLoan = await poolNAV.debt(tokenIds[0]);
      expect(debtLoan).to.equal(parseEther('9'));
      expect(currentNAV).to.closeTo(parseEther('9.0037'), parseEther('0.001'));
    });


    it('after 10 days - should include interest', async () => {
      await time.increase(10 * ONE_DAY);
      const now = await time.latest();

      const currentNAV = await poolNAV.currentNAV();
      const debtLoan = await poolNAV.debt(tokenIds[0]);
      expect(debtLoan).to.closeTo(parseEther('9.029'), parseEther('0.001'));
      expect(currentNAV).to.closeTo(parseEther('9.02839'), parseEther('0.001'));
      const value = await securitizationPoolValueService.getExpectedAssetsValue(securitizationPoolContract.address, now);
      expect(value).to.closeTo(parseEther('9.02839'), parseEther('0.001'));
    });
    it('next 20 days - on maturity date', async () => {
      await time.increase(20 * ONE_DAY);
      const now = await time.latest();
      // const value = await securitizationPoolValueService.getExpectedAssetsValue(securitizationPoolContract.address, now);
      // console.log("ASSET", value);
      const currentNAV = await poolNAV.currentNAV();
      const debtLoan = await poolNAV.debt(tokenIds[0]);
      expect(debtLoan).to.closeTo(parseEther('9.089'), parseEther('0.001'));
      expect(currentNAV).to.closeTo(parseEther('9.078'), parseEther('0.001'));
    });
/*
    xit('should repay now', async () => {
      await stableCoin.connect(untangledAdminSigner).approve(loanRepaymentRouter.address, unlimitedAllowance);
      await loanRepaymentRouter
          .connect(untangledAdminSigner)
          .repayInBatch([tokenIds[0]], [parseEther('10')], stableCoin.address);
*/
    it('should revert if write off loan before grace period', async () => {
      await time.increase(2 * ONE_DAY);
      await expect(poolNAV.writeOff(tokenIds[0])).to.be.revertedWith('maturity-date-in-the-future');
    });

    it('overdue 6 days - should write off after grace period', async () => {
      await time.increase(3 * ONE_DAY);
      await poolNAV.writeOff(tokenIds[0]);
      await time.increase(1 * ONE_DAY);
      const currentNAV = await poolNAV.currentNAV();
      expect(currentNAV).to.closeTo(parseEther('4.5543'), parseEther('0.005'));
    });
    it('overdue next 30 days - should write off after collection period', async () => {
      await time.increase(30 * ONE_DAY);
      await poolNAV.writeOff(tokenIds[0]);
      const currentNAV = await poolNAV.currentNAV();
      expect(currentNAV).to.equal(parseEther('0'));
    });

    it('should repay successfully', async () => {
      await stableCoin.connect(untangledAdminSigner).approve(loanRepaymentRouter.address, unlimitedAllowance);
      await loanRepaymentRouter
        .connect(untangledAdminSigner)
        .repayInBatch([tokenIds[0]], [parseEther('10')], stableCoin.address);

    });
  });

});
