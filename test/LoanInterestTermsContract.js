const { ethers } = require('hardhat');
const { expect } = require('./shared/expect.js');
const { mainFixture } = require('./shared/fixtures');
const { BigNumber } = require('ethers');
const {
  genSalt,
  packTermsContractParameters,
  interestRateFixedPoint,
  saltFromOrderValues,
  debtorsFromOrderAddresses,
  genLoanAgreementIds, unlimitedAllowance
} = require('./utils');
const { parseEther, parseUnits, formatEther, formatBytes32String } = ethers.utils;
const dayjs = require('dayjs');
const _ = require('lodash');
const { admin } = require('@openzeppelin/truffle-upgrades');
const { time } = require('@nomicfoundation/hardhat-network-helpers');

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
describe('LoanInterestTermsContract', () => {
  let stableCoin;
  let securitizationManagerContract;
  let loanKernelContract;
  let loanRepaymentRouterContract;
  let loanAssetTokenContract;
  let loanRegistryContract;
  let uniqueIdentityContract;
  let registryContract;
  let loanInterestTermsContract;
  let distributionOperator;
  let distributionTranche;
  let securitizationPoolContract;
  let tokenIds;

  // Wallets
  let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer,
    impersonationKernel;

  before('create fixture', async () => {
    [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer, impersonationKernel] =
      await ethers.getSigners();

    ({
      stableCoin,
      uniqueIdentityContract,
      loanAssetTokenContract,
      loanInterestTermsContract,
      loanRegistryContract,
      loanKernelContract,
      loanRepaymentRouterContract,
      securitizationManagerContract,
      distributionOperator,
      distributionTranche,
      registryContract,
    } = await mainFixture());

    const POOL_CREATOR_ROLE = await securitizationManagerContract.POOL_CREATOR();
    await securitizationManagerContract.grantRole(POOL_CREATOR_ROLE, poolCreatorSigner.address);
    // Create new pool
    const transaction = await securitizationManagerContract
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
        loanInterestTermsContract.connect(untangledAdminSigner).registerTermStart(agreementID),
      ).to.be.revertedWith(
        'LoanInterestTermsContract: Only for LoanKernel.',
      );
    });
    it('should start loan successfully', async () => {
      await registryContract.setLoanKernel(impersonationKernel.address);
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
      await registryContract.setLoanKernel(loanKernelContract.address);
      const orderAddresses = [
        securitizationPoolContract.address,
        stableCoin.address,
        loanRepaymentRouterContract.address,
        loanInterestTermsContract.address,
        relayer.address,
        borrowerSigner.address,
        borrowerSigner.address,
      ];

      const salt = genSalt();
      const salt1 = genSalt();
      const riskScore = '50';
      expirationTimestamps = dayjs(new Date()).add(7, 'days').unix();

      const orderValues = [
        CREDITOR_FEE,
        ASSET_PURPOSE,
        principalAmount.toString(),
        (principalAmount).toString(),
        expirationTimestamps,
        expirationTimestamps,
        salt,
        salt1,
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
        amortizationUnitType: 1,
        gracePeriodInDays: 2,
        principalAmount: principalAmount,
        termLengthUnits: _.ceil(termInDaysLoan * 24),
        interestRateFixedPoint: interestRateFixedPoint(interestRatePercentage),
      });

      const termsContractParameters = [termsContractParameter, termsContractParameter_1];

      const salts = saltFromOrderValues(orderValues, termsContractParameters.length);
      const debtors = debtorsFromOrderAddresses(orderAddresses, termsContractParameters.length);

      tokenIds = genLoanAgreementIds(
        loanRepaymentRouterContract.address,
        debtors,
        loanInterestTermsContract.address,
        termsContractParameters,
        salts
      );

      await loanKernelContract.fillDebtOrder(orderAddresses, orderValues, termsContractParameters, tokenIds);
      await stableCoin.connect(untangledAdminSigner).approve(loanRepaymentRouterContract.address, unlimitedAllowance);
    });
    it('should return correct expected principal and expected interest', async () => {
      const now = await time.latest();
      const duration = YEAR_LENGTH_IN_SECONDS
      const {
        expectedPrincipal,
        expectedInterest,
      } = await loanInterestTermsContract.getExpectedRepaymentValues(tokenIds[0], now + duration);
      const repaidPrincipalAmount = await loanInterestTermsContract.repaidPrincipalAmounts(tokenIds[0]);
      expect(expectedPrincipal).equal(BigNumber.from(principalAmount.toString()).sub(repaidPrincipalAmount));

      const expectInterest = calculateInterestForDuration(principalAmount, interestRatePercentage, duration);
      expect(expectedInterest).closeTo(expectInterest.toString(), parseEther('0.001'));
    });
  });
  describe('#registerRepayment', () => {
    it('should revert if caller is not LoanRepaymentRouter contract address', async () => {
      const agreement = tokenIds[0];
      const payer =  untangledAdminSigner.address
      const beneficiary = await securitizationManagerContract.address;
      const unitOfRepayment = parseEther('100')
      const tokenAddress = stableCoin.address;
      await expect(
        loanInterestTermsContract.registerRepayment(agreement, payer, beneficiary, unitOfRepayment, tokenAddress),
      ).to.be.revertedWith('LoanInterestTermsContract: Only for Repayment Router.');
    });
    it('should execute successfully', async () => {
      await time.increase(YEAR_LENGTH_IN_SECONDS)
      const now = await time.latest();
      const timestampNextBlock = now +1
      const {
        expectedPrincipal,
        expectedInterest,
      } = await loanInterestTermsContract.getExpectedRepaymentValues(tokenIds[0], timestampNextBlock);
      await loanRepaymentRouterContract
        .connect(untangledAdminSigner)
        .repayInBatch([tokenIds[0]], [expectedInterest.add(expectedPrincipal)], stableCoin.address);

      const repaidPrincipalAmounts = await loanInterestTermsContract.repaidPrincipalAmounts(tokenIds[0]);
      expect(repaidPrincipalAmounts).equal(expectedPrincipal);
      const repaidInterestAmounts = await loanInterestTermsContract.repaidInterestAmounts(tokenIds[0]);
      expect(repaidInterestAmounts).equal(expectedInterest, parseEther('0.02'));
      const loanEntry = await loanRegistryContract.entries(tokenIds[0]);
      expect(loanEntry.lastRepayTimestamp).equal(timestampNextBlock);
    });

  });

  describe('#registerConcludeLoan', () => {
    it('should revert if caller is not LoanKernel contract address', async () => {
      await expect(
        loanInterestTermsContract.connect(untangledAdminSigner).registerConcludeLoan(agreementID),
      ).to.be.revertedWith(
        'LoanInterestTermsContract: Only for LoanKernel.',
      );
    });
    it('should revert if repayment for loan has not been completed', async () => {
      await expect(
        loanInterestTermsContract.connect(impersonationKernel).registerConcludeLoan(tokenIds[1]),
      ).to.be.revertedWith(
        'LoanInterestTermsContract: Only for LoanKernel.',
      );
    });
    it('should register conclude loan successfully', async () => {
      const completedRepayment = await loanInterestTermsContract.completedRepayment(tokenIds[0]);
      expect(completedRepayment).equal(true);
    });
  });

  describe('#getInterestRate', () => {

  });
  describe('#getMultiExpectedRepaymentValues', () => {

  });
  describe('#isCompletedRepayments', () => {

  });
  describe('#getValueRepaidToDate', () => {

  });


});