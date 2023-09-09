const { ethers } = require('hardhat');
const { expect } = require('./shared/expect.js');
const { mainFixture } = require('./shared/fixtures');

describe('LoanInterestTermsContract', () => {
  let stableCoin;
  let securitizationManagerContract;
  let loanKernelContract;
  let loanRepaymentRouterContract;
  let loanAssetTokenContract;
  let uniqueIdentityContract;
  let registryContract;
  let loanInterestTermsContract;
  let distributionOperator;
  let distributionTranche;

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
      loanKernelContract,
      loanRepaymentRouterContract,
      securitizationManagerContract,
      distributionOperator,
      distributionTranche,
      registryContract,
    } = await mainFixture());

  });

  const agreementID = '0x979b5e9fab60f9433bf1aa924d2d09636ae0f5c10e2c6a8a58fe441cd1414d7f';
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

  describe('#registerConcludeLoan', () => {
    it('should revert if caller is not LoanKernel contract address', async () => {
      await expect(
        loanInterestTermsContract.connect(untangledAdminSigner).registerConcludeLoan(agreementID),
      ).to.be.revertedWith(
        'LoanInterestTermsContract: Only for LoanKernel.',
      );

    });
    it('should register conclude loan successfully', () => {

    });
  });
  describe('#registerRepayment', () => {
    it('should revert if caller is not LoanRepaymentRouter contract address', () => {

    });

  });
  describe('#getInterestRate', () => {

  });
  describe('#getMultiExpectedRepaymentValues', () => {

  });
  describe('#getExpectedRepaymentValues', () => {

  });
  describe('#isCompletedRepayments', () => {

  });
  describe('#getValueRepaidToDate', () => {

  });


});