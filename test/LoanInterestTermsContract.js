const { ethers } = require('hardhat');
const { expect } = require('./shared/expect.js');
const { BigNumber } = require('ethers');
const {
  genSalt,
  packTermsContractParameters,
  interestRateFixedPoint,
  saltFromOrderValues,
  debtorsFromOrderAddresses,
  genLoanAgreementIds,
  unlimitedAllowance,
} = require('./utils');
const { parseEther, parseUnits, formatEther, formatBytes32String } = ethers.utils;
const dayjs = require('dayjs');
const _ = require('lodash');
const { admin } = require('@openzeppelin/truffle-upgrades');
const {
  time,
  impersonateAccount,
  stopImpersonatingAccount,
  setBalance,
} = require('@nomicfoundation/hardhat-network-helpers');
const { parse } = require('dotenv');
const { setup } = require('./setup.js');

const ONE_DAY = 86400;

const YEAR_LENGTH_IN_SECONDS = 31536000; // Number of seconds in a year (approximately)
function calculateInterestForDuration(principalAmount, interestRate, durationLengthInSec) {
  // Calculate the interest rate as a fraction
  const interestRateFraction = interestRate * (1 / 100);

  // Calculate the compound interest using the formula
  const compoundInterest =
    principalAmount * Math.pow(1 + interestRateFraction / YEAR_LENGTH_IN_SECONDS, durationLengthInSec) -
    principalAmount;

  return compoundInterest;
}
describe('LoanInterestTermsContract', () => {
  let stableCoin;
  let securitizationManager;
  let loanKernel;
  let loanRepaymentRouter;
  let loanAssetTokenContract;
  let loanRegistry;
  let uniqueIdentity;
  let registry;
  let loanInterestTerms;
  let distributionOperator;
  let distributionTranche;
  let securitizationPoolContract;
  let tokenIds;

  // Wallets
  let untangledAdminSigner,
    poolCreatorSigner,
    originatorSigner,
    borrowerSigner,
    lenderSigner,
    relayer,
    impersonationKernel;

  before('create fixture', async () => {
    [
      untangledAdminSigner,
      poolCreatorSigner,
      originatorSigner,
      borrowerSigner,
      lenderSigner,
      relayer,
      impersonationKernel,
    ] = await ethers.getSigners();

    ({
      stableCoin,
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
    } = await setup());

    const POOL_CREATOR_ROLE = await securitizationManager.POOL_CREATOR();
    await securitizationManager.grantRole(POOL_CREATOR_ROLE, poolCreatorSigner.address);
    // Create new pool
    const transaction = await securitizationManager
      .connect(poolCreatorSigner)
      .newPoolInstance(stableCoin.address, '100000');
    const receipt = await transaction.wait();
    const [securitizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;

    securitizationPoolContract = await ethers.getContractAt('SecuritizationPool', securitizationPoolAddress);
  });

  const agreementID = '0x979b5e9fab60f9433bf1aa924d2d09636ae0f5c10e2c6a8a58fe441cd1414d7f';
  let expirationTimestamps;
  const CREDITOR_FEE = '0';
  const ASSET_PURPOSE = '0';
  const inputAmount = 10;
  const inputPrice = 15;
  const principalAmount = 5000000000000000000;
  const interestRatePercentage = 5;
  describe('#registerTermStart', () => {
    it('should revert if caller is not LoanKernel contract address', async () => {
      await expect(
        loanInterestTermsContract.connect(untangledAdminSigner).registerTermStart(agreementID)
      ).to.be.revertedWith('LoanInterestTermsContract: Only for LoanKernel.');
    });
    it('should start loan successfully', async () => {
      await registry.setLoanKernel(impersonationKernel.address);
      await loanInterestTermsContract.connect(impersonationKernel).registerTermStart(agreementID);
      expect(await loanInterestTermsContract.startedLoan(agreementID)).equal(true);
    });
    it('should revert if the loan has started', async () => {
      await expect(
        loanInterestTermsContract.connect(impersonationKernel).registerTermStart(agreementID)
      ).to.be.revertedWith('LoanInterestTermsContract: Loan has started!');
    });
  });

  describe('#getExpectedRepaymentValues', () => {
    before('upload a loan', async () => {
      await registry.setLoanKernel(loanKernel.address);
      const orderAddresses = [
        securitizationPoolContract.address,
        stableCoin.address,
        loanRepaymentRouter.address,
        loanInterestTermsContract.address,
        relayer.address,
        borrowerSigner.address, // for loan 0
        borrowerSigner.address, // for loan 1
        borrowerSigner.address, // for loan 2
        borrowerSigner.address, // for loan 3
        borrowerSigner.address, // for loan 4
      ];

      const salt = genSalt();
      const salt1 = genSalt();
      const salt2 = genSalt();
      const salt3 = genSalt();
      const salt4 = genSalt();
      const riskScore = '50';
      expirationTimestamps = dayjs(new Date()).add(7, 'days').unix();

      const orderValues = [
        CREDITOR_FEE,
        ASSET_PURPOSE,
        principalAmount.toString(),
        principalAmount.toString(),
        principalAmount.toString(),
        principalAmount.toString(),
        principalAmount.toString(),
        expirationTimestamps,
        expirationTimestamps,
        expirationTimestamps,
        expirationTimestamps,
        expirationTimestamps,
        salt,
        salt1,
        salt2,
        salt3,
        salt4,
        riskScore,
        riskScore,
        riskScore,
        riskScore,
        riskScore,
      ];

      const termInDaysLoan = 10;
      const termsContractParameter = packTermsContractParameters({
        amortizationUnitType: 1,
        gracePeriodInDays: 2,
        principalAmount: principalAmount,
        termLengthUnits: _.ceil(termInDaysLoan * 24),
        interestRateFixedPoint: interestRateFixedPoint(interestRatePercentage),
      });
      const termsContractParameter_1 = packTermsContractParameters({
        amortizationUnitType: 2,
        gracePeriodInDays: 2,
        principalAmount: principalAmount,
        termLengthUnits: _.ceil(termInDaysLoan * 24),
        interestRateFixedPoint: interestRateFixedPoint(interestRatePercentage),
      });

      const termsContractParameter_2 = packTermsContractParameters({
        amortizationUnitType: 3,
        gracePeriodInDays: 2,
        principalAmount: principalAmount,
        termLengthUnits: _.ceil(termInDaysLoan * 24),
        interestRateFixedPoint: interestRateFixedPoint(interestRatePercentage),
      });

      const termsContractParameter_3 = packTermsContractParameters({
        amortizationUnitType: 4,
        gracePeriodInDays: 2,
        principalAmount: principalAmount,
        termLengthUnits: _.ceil(termInDaysLoan * 24),
        interestRateFixedPoint: interestRateFixedPoint(interestRatePercentage),
      });
      const termsContractParameter_4 = packTermsContractParameters({
        amortizationUnitType: 5,
        gracePeriodInDays: 2,
        principalAmount: principalAmount,
        termLengthUnits: _.ceil(termInDaysLoan * 24),
        interestRateFixedPoint: interestRateFixedPoint(interestRatePercentage),
      });

      const termsContractParameters = [termsContractParameter, termsContractParameter_1, termsContractParameter_2, termsContractParameter_3, termsContractParameter_4];

      const salts = saltFromOrderValues(orderValues, termsContractParameters.length);
      const debtors = debtorsFromOrderAddresses(orderAddresses, termsContractParameters.length);

      tokenIds = genLoanAgreementIds(
        loanRepaymentRouter.address,
        debtors,
        loanInterestTermsContract.address,
        termsContractParameters,
        salts
      );

      await loanKernel.fillDebtOrder(orderAddresses, orderValues, termsContractParameters, tokenIds);
      await stableCoin.connect(untangledAdminSigner).approve(loanRepaymentRouter.address, unlimitedAllowance);
    });
    it('should return correct expected principal and expected interest', async () => {
      const now = await time.latest();
      const duration = YEAR_LENGTH_IN_SECONDS;
      const { expectedPrincipal, expectedInterest } = await loanInterestTermsContract.getExpectedRepaymentValues(
        tokenIds[0],
        now + duration
      );
      const repaidPrincipalAmount = await loanInterestTermsContract.repaidPrincipalAmounts(tokenIds[0]);
      expect(expectedPrincipal).equal(BigNumber.from(principalAmount.toString()).sub(repaidPrincipalAmount));

      const expectInterest = calculateInterestForDuration(principalAmount, interestRatePercentage, duration);
      expect(expectedInterest).closeTo(expectInterest.toString(), parseEther('0.001'));
    });
  });
  describe('#registerRepayment', () => {
    it('should revert if caller is not LoanRepaymentRouter contract address', async () => {
      const agreement = tokenIds[0];
      const payer = untangledAdminSigner.address;
      const beneficiary = await securitizationManager.address;
      const unitOfRepayment = parseEther('100');
      const tokenAddress = stableCoin.address;
      await expect(
        loanInterestTermsContract.registerRepayment(agreement, payer, beneficiary, unitOfRepayment, tokenAddress)
      ).to.be.revertedWith('LoanInterestTermsContract: Only for Repayment Router.');
    });
    it('should execute successfully', async () => {
      await time.increase(YEAR_LENGTH_IN_SECONDS);
      const now = await time.latest();
      const timestampNextBlock = now + 1;
      const { expectedPrincipal, expectedInterest } = await loanInterestTermsContract.getExpectedRepaymentValues(
        tokenIds[0],
        timestampNextBlock
      );
      await loanRepaymentRouter
        .connect(untangledAdminSigner)
        .repayInBatch([tokenIds[0]], [expectedInterest.add(expectedPrincipal)], stableCoin.address);

      const repaidPrincipalAmounts = await loanInterestTermsContract.repaidPrincipalAmounts(tokenIds[0]);
      expect(repaidPrincipalAmounts).equal(expectedPrincipal);
      const repaidInterestAmounts = await loanInterestTermsContract.repaidInterestAmounts(tokenIds[0]);
      expect(repaidInterestAmounts).equal(expectedInterest, parseEther('0.02'));
      const loanEntry = await loanRegistry.entries(tokenIds[0]);
      expect(loanEntry.lastRepayTimestamp).equal(timestampNextBlock);
    });
    it('should execute part of repayment amount successfully', async () => {
      await time.increase(YEAR_LENGTH_IN_SECONDS);
      const now = await time.latest();
      const timestampNextBlock = now + 1;
      const { expectedInterest } = await loanInterestTermsContract.getExpectedRepaymentValues(
        tokenIds[2],
        timestampNextBlock
      );
      await loanRepaymentRouter
        .connect(untangledAdminSigner)
        .repayInBatch([tokenIds[2]], [expectedInterest.add(parseEther('0.01'))], stableCoin.address);

      const repaidPrincipalAmounts = await loanInterestTermsContract.repaidPrincipalAmounts(tokenIds[2]);
      expect(repaidPrincipalAmounts).equal(parseEther('0.01'));
      const repaidInterestAmounts = await loanInterestTermsContract.repaidInterestAmounts(tokenIds[2]);
      expect(repaidInterestAmounts).equal(expectedInterest, parseEther('0.02'));
      const loanEntry = await loanRegistry.entries(tokenIds[2]);
      expect(loanEntry.lastRepayTimestamp).equal(timestampNextBlock);
    });
  });

  describe('Get Info', async () => {
    it('#getValueRepaidToDate', async () => {
      const result = await loanInterestTermsContract.getValueRepaidToDate(tokenIds[0]);

      expect(result.map((x) => formatEther(x))).to.deep.equal(['5.0', '0.256355506673463652']);
    });

    it('#isCompletedRepayments', async () => {
      const result = await loanInterestTermsContract.isCompletedRepayments([tokenIds[0]]);

      expect(result).to.deep.equal([true]);
    });

    it('#getMultiExpectedRepaymentValues', async () => {
      const nextTime = dayjs(new Date()).add(7, 'days').unix();
      const result = await loanInterestTermsContract.getMultiExpectedRepaymentValues([agreementID], nextTime);

      expect(result.map((x) => x.map((y) => formatEther(y)))).to.deep.equal([['0.0'], ['0.0']]);
    });
  });

  describe('#registerConcludeLoan', () => {
    it('should revert if caller is not LoanKernel contract address', async () => {
      await expect(
        loanInterestTermsContract.connect(untangledAdminSigner).registerConcludeLoan(agreementID)
      ).to.be.revertedWith('LoanInterestTermsContract: Only for LoanKernel.');
    });
    it('should revert if repayment for loan has not been completed', async () => {
      await impersonateAccount(loanKernel.address);
      await setBalance(loanKernel.address, parseEther('1'));
      const signer = await ethers.getSigner(loanKernel.address);
      await expect(loanInterestTermsContract.connect(signer).registerConcludeLoan(tokenIds[1])).to.be.revertedWith(
        'Debtor has not completed repayment yet.'
      );

      await stopImpersonatingAccount(loanKernel.address);
    });
    it('should register conclude loan successfully', async () => {
      const completedRepayment = await loanInterestTermsContract.completedRepayment(tokenIds[0]);
      expect(completedRepayment).equal(true);
    });
  });

  describe('#getInterestRate', async () => {
    it('should unpack interest rate correctly', async () => {
      const interestRate = await loanInterestTermsContract.getInterestRate(tokenIds[0]);
      expect(interestRate).equal(BigNumber.from(interestRateFixedPoint(interestRatePercentage).toString()));
    });
  });

  describe('#isCompletedRepayments', async () => {
    it('should return repayment status of agreementIds', async () => {
      const repaymentStatus = await loanInterestTermsContract.isCompletedRepayments(tokenIds);
      expect(repaymentStatus).to.deep.equal([true, false, false, false, false])
    });
  });
  describe('#getValueRepaidToDate', async () => {
    it('should return current repaid principal and interest amount of an agreementId', async () => {
      const [repaidPrincipal, repaidInterest] = await loanInterestTermsContract.getValueRepaidToDate(tokenIds[0]);
      const expectPrincipalAmount = await loanInterestTermsContract.repaidPrincipalAmounts(tokenIds[0]);
      const expectInterestAmount = await loanInterestTermsContract.repaidInterestAmounts(tokenIds[0]);
      expect(repaidPrincipal).to.equal(expectPrincipalAmount)
      expect(repaidInterest).to.equal(expectInterestAmount)
    });
  });
  describe('#getMultiExpectedRepaymentValues', async () => {
    it('should return current repaid principal and interest amount of multiple agreementIds', async () => {
      const [repaidPrincipal, repaidInterest] = await loanInterestTermsContract.getValueRepaidToDate(tokenIds[0]);
      const expectPrincipalAmount = await loanInterestTermsContract.repaidPrincipalAmounts(tokenIds[0]);
      const expectInterestAmount = await loanInterestTermsContract.repaidInterestAmounts(tokenIds[0]);
      const [repaidPrincipal1, repaidInterest1] = await loanInterestTermsContract.getValueRepaidToDate(tokenIds[1]);
      const expectPrincipalAmount1 = await loanInterestTermsContract.repaidPrincipalAmounts(tokenIds[1]);
      const expectInterestAmount1 = await loanInterestTermsContract.repaidInterestAmounts(tokenIds[1]);
      expect(repaidPrincipal).to.equal(expectPrincipalAmount);
      expect(repaidInterest).to.equal(expectInterestAmount);
      expect(repaidPrincipal1).to.equal(expectPrincipalAmount1);
      expect(repaidInterest1).to.equal(expectInterestAmount1);
    });
  });
});
