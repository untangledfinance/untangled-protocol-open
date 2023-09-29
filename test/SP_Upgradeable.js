const { ethers, upgrades } = require('hardhat');
const { deployments } = require('hardhat');
const _ = require('lodash');
const dayjs = require('dayjs');
const { expect } = require('chai');
const { time } = require('@nomicfoundation/hardhat-network-helpers');

const { BigNumber } = ethers;
const { parseEther, parseUnits, formatEther, formatBytes32String } = ethers.utils;
const { presignedMintMessage } = require('./shared/uid-helper.js');

const {
  unlimitedAllowance,
  ZERO_ADDRESS,
  genLoanAgreementIds,
  saltFromOrderValues,
  debtorsFromOrderAddresses,
  packTermsContractParameters,
  interestRateFixedPoint,
  genSalt,
} = require('./utils.js');
const { setup } = require('./setup.js');
const { SaleType } = require('./shared/constants.js');

const ONE_DAY = 86400;
const RATE_SCALING_FACTOR = 10 ** 4;

describe('SP_Upgradeable', () => {
  let stableCoin;
  let loanAssetTokenContract;
  let loanInterestTermsContract;
  let loanKernel;
  let loanRepaymentRouter;
  let securitizationManager;
  let securitizationPoolContract;
  let secondSecuritizationPool;
  let tokenIds;
  let uniqueIdentity;
  let distributionOperator;
  let sotToken;
  let jotToken;
  let distributionTranche;
  let mintedIncreasingInterestTGE;
  let jotMintedIncreasingInterestTGE;
  let securitizationPoolValueService;
  let factoryAdmin;
  let securitizationPoolImpl;

  // Wallets
  let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer;
  before('create fixture', async () => {
    [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer] =
      await ethers.getSigners();

    ({
      stableCoin,
      loanAssetTokenContract,
      loanInterestTermsContract,
      loanKernel,
      loanRepaymentRouter,
      securitizationManager,
      uniqueIdentity,
      distributionOperator,
      distributionTranche,
      securitizationPoolValueService,
      factoryAdmin,
      securitizationPoolImpl,
    } = await setup());

    await stableCoin.transfer(lenderSigner.address, parseEther('1000'));

    await stableCoin.connect(untangledAdminSigner).approve(loanRepaymentRouter.address, unlimitedAllowance);

    // Gain UID
    const UID_TYPE = 0;
    const chainId = await getChainId();
    const expiredAt = dayjs().unix() + 86400 * 1000;
    const nonce = 0;
    const ethRequired = parseEther('0.00083');

    const uidMintMessage = presignedMintMessage(
      lenderSigner.address,
      UID_TYPE,
      expiredAt,
      uniqueIdentity.address,
      nonce,
      chainId
    );
    const signature = await untangledAdminSigner.signMessage(uidMintMessage);
    await uniqueIdentity.connect(lenderSigner).mint(UID_TYPE, expiredAt, signature, { value: ethRequired });
  });

  describe('#security pool', async () => {
    it('Create pool', async () => {
      const POOL_CREATOR_ROLE = await securitizationManager.POOL_CREATOR();
      await securitizationManager.grantRole(POOL_CREATOR_ROLE, poolCreatorSigner.address);
      // Create new pool
      let transaction = await securitizationManager
        .connect(poolCreatorSigner)
        .newPoolInstance(stableCoin.address, '100000');
      let receipt = await transaction.wait();
      let [securitizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;

      securitizationPoolContract = await ethers.getContractAt('SecuritizationPool', securitizationPoolAddress);
      await securitizationPoolContract
        .connect(poolCreatorSigner)
        .grantRole(await securitizationPoolContract.ORIGINATOR_ROLE(), originatorSigner.address);

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

  describe('Upgradeables', async () => {
    it('Should upgrade to new Implementation successfully', async () => {
      const SecuritizationPoolV2 = await ethers.getContractFactory('SecuritizationPoolV2');
      const spV2Impl = await SecuritizationPoolV2.deploy();

      let test = await spV2Impl.greeting();
      console.log(test);
      test = await spV2Impl.hello();
      console.log(test);

      const spImpl = await factoryAdmin.getProxyImplementation(securitizationPoolContract.address);

      expect(securitizationPoolImpl.address).to.be.eq(spImpl);

      // Update new logic
      await factoryAdmin.connect(untangledAdminSigner).upgrade(securitizationPoolContract.address, spV2Impl.address);

      const newSpImpl = await factoryAdmin.getProxyImplementation(securitizationPoolContract.address);

      expect(spV2Impl.address).to.be.eq(newSpImpl);

      const result = await securitizationPoolContract.hello();

      expect(result).to.be.eq('Hello world');
    });
  });
});
