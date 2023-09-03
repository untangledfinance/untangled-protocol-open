const { ethers, upgrades } = require('hardhat');
const { deployments } = require('hardhat');
const _ = require('lodash');
const dayjs = require('dayjs');
const { expect } = require('./shared/expect.js');

const { parseEther, parseUnits, formatEther } = ethers.utils;

const {
  unlimitedAllowance,
  genLoanAgreementIds,
  saltFromOrderValues,
  debtorsFromOrderAddresses,
  packTermsContractParameters,
  interestRateFixedPoint,
  genSalt,
} = require('./utils.js');

const ONE_DAY = 86400;
describe('LoanAssetToken', () => {
  let stableCoin;
  let registry;
  let loanAssetTokenContract;
  let loanInterestTermsContract;
  let loanRegistry;
  let loanKernel;
  let loanRepaymentRouter;
  let securitizationManager;
  let securitizationPoolContract;
  let securitizationPoolValueService;
  let securitizationPoolImpl;
  let tokenIds;

  // Wallets
  let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer;
  before('create fixture', async () => {
    [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer] =
      await ethers.getSigners();

    const tokenFactory = await ethers.getContractFactory('TestERC20');
    stableCoin = await tokenFactory.deploy('cUSD', 'cUSD', parseEther('10000000000000000'));
    await stableCoin.transfer(lenderSigner.address, parseEther('1000'));

    const Registry = await ethers.getContractFactory('Registry');
    registry = await upgrades.deployProxy(Registry, []);

    const SecuritizationManager = await ethers.getContractFactory('SecuritizationManager');
    securitizationManager = await upgrades.deployProxy(SecuritizationManager, [registry.address]);
    const SecuritizationPoolValueService = await ethers.getContractFactory('SecuritizationPoolValueService');
    securitizationPoolValueService = await upgrades.deployProxy(SecuritizationPoolValueService, [registry.address]);

    const LoanInterestTermsContract = await ethers.getContractFactory('LoanInterestTermsContract');
    loanInterestTermsContract = await upgrades.deployProxy(LoanInterestTermsContract, [registry.address]);
    const LoanRegistry = await ethers.getContractFactory('LoanRegistry');
    loanRegistry = await upgrades.deployProxy(LoanRegistry, [registry.address]);
    const LoanKernel = await ethers.getContractFactory('LoanKernel');
    loanKernel = await upgrades.deployProxy(LoanKernel, [registry.address]);
    const LoanRepaymentRouter = await ethers.getContractFactory('LoanRepaymentRouter');
    loanRepaymentRouter = await upgrades.deployProxy(LoanRepaymentRouter, [registry.address]);

    await stableCoin.connect(untangledAdminSigner).approve(loanRepaymentRouter.address, unlimitedAllowance);

    await registry.setLoanInterestTermsContract(loanInterestTermsContract.address);
    await registry.setLoanRegistry(loanRegistry.address);
    await registry.setLoanKernel(loanKernel.address);
    await registry.setLoanRepaymentRouter(loanRepaymentRouter.address);
    await registry.setSecuritizationPoolValueService(securitizationPoolValueService.address);

    const LoanAssetToken = await ethers.getContractFactory('LoanAssetToken');
    loanAssetTokenContract = await upgrades.deployProxy(LoanAssetToken, [registry.address, 'TEST', 'TST', 'test.com'], {
      initializer: 'initialize(address,string,string,string)',
    });

    await registry.setLoanAssetToken(loanAssetTokenContract.address);

    const SecuritizationPool = await ethers.getContractFactory('SecuritizationPool');
    securitizationPoolImpl = await SecuritizationPool.deploy();

    await registry.setSecuritizationPool(securitizationPoolImpl.address);
    await registry.setSecuritizationManager(securitizationManager.address);
  });

  describe('#security pool', async () => {
    it('Create pool', async () => {
      const POOL_CREATOR_ROLE = await securitizationManager.POOL_CREATOR();
      await securitizationManager.grantRole(POOL_CREATOR_ROLE, poolCreatorSigner.address);
      // Create new pool
      const transaction = await securitizationManager
        .connect(poolCreatorSigner)
        .newPoolInstance(stableCoin.address, '100000');
      const receipt = await transaction.wait();
      const [securitizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;

      securitizationPoolContract = await ethers.getContractAt('SecuritizationPool', securitizationPoolAddress);

      const oneDayInSecs = 1 * 24 * 3600;
      const halfOfADay = oneDayInSecs / 2;

      const riskScore = {
        daysPastDue: oneDayInSecs,
        advanceRate: 950000,
        penaltyRate: 900000,
        interestRate: 910000,
        probabilityOfDefault: 800000,
        lossGivenDefault: 810000,
        gracePeriod: halfOfADay,
        collectionPeriod: halfOfADay,
        writeOffAfterGracePeriod: halfOfADay,
        writeOffAfterCollectionPeriod: halfOfADay,
      };
      const daysPastDues = [riskScore.daysPastDue];
      const ratesAndDefaults = [
        riskScore.advanceRate,
        riskScore.penaltyRate,
        riskScore.interestRate,
        riskScore.probabilityOfDefault,
        riskScore.lossGivenDefault,
      ];
      const periodsAndWriteOffs = [
        riskScore.gracePeriod,
        riskScore.collectionPeriod,
        riskScore.writeOffAfterGracePeriod,
        riskScore.writeOffAfterCollectionPeriod,
      ];

      await securitizationPoolContract
        .connect(poolCreatorSigner)
        .setupRiskScores(daysPastDues, ratesAndDefaults, periodsAndWriteOffs);
    });
  });

  describe('#mint', async () => {
    it('No one than LoanKernel can mint', async () => {
      await expect(
        loanAssetTokenContract.connect(untangledAdminSigner)['mint(address,uint256)'](lenderSigner.address, 1)
      ).to.be.revertedWith(
        `AccessControl: account ${untangledAdminSigner.address.toLowerCase()} is missing role 0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6`
      );
    });

    it('Only Loan Kernel can mint', async () => {
      const orderAddresses = [
        securitizationPoolContract.address,
        stableCoin.address,
        loanRepaymentRouter.address,
        loanInterestTermsContract.address,
        relayer.address,
        borrowerSigner.address,
      ];

      const inputAmount = 10;
      const inputPrice = 15;

      const CREDITOR_FEE = '0';
      const ASSET_PURPOSE = '0';
      const salt = genSalt();
      const riskScore = parseUnits('11853', 8).toString();
      const expirationTimestamps = dayjs(new Date()).add(7, 'days').unix();
      const principalAmount = _.round(inputAmount * inputPrice * 100);

      const orderValues = [
        CREDITOR_FEE,
        ASSET_PURPOSE,
        parseEther(principalAmount.toString()),
        expirationTimestamps,
        salt,
        riskScore,
      ];

      const termInDaysLoan = 10;
      const interestRatePercentage = 5;
      const termsContractParameter = packTermsContractParameters({
        amortizationUnitType: 1,
        gracePeriodInDays: 2,
        principalAmount,
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

      await loanKernel.fillDebtOrder(orderAddresses, orderValues, termsContractParameters, tokenIds);

      const ownerOfAgreement = await loanAssetTokenContract.ownerOf(tokenIds[0]);
      expect(ownerOfAgreement).equal(securitizationPoolContract.address);

      const balanceOfPool = await loanAssetTokenContract.balanceOf(securitizationPoolContract.address);
      expect(balanceOfPool).equal(tokenIds.length);
    });
  });

  describe('#burn', async () => {
    it('No one than LoanKernel contract can burn', async () => {
      await expect(loanAssetTokenContract.connect(untangledAdminSigner).burn(tokenIds[0])).to.be.revertedWith(
        `ERC721: caller is not token owner or approved`
      );
    });

    it('only LoanKernel contract can burn', async () => {
      await loanRepaymentRouter
        .connect(untangledAdminSigner)
        .repayInBatch([tokenIds[0]], [parseEther('100')], stableCoin.address);

      await expect(loanAssetTokenContract.ownerOf(tokenIds[0])).to.be.revertedWith(`ERC721: invalid token ID`);

      const balanceOfPool = await loanAssetTokenContract.balanceOf(securitizationPoolContract.address);
      expect(balanceOfPool).equal(tokenIds.length - 1);
    });
  });
});
