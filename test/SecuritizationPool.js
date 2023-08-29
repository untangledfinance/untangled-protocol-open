const { ethers} = require('hardhat');
const { deployments } = require('hardhat');
const { BigNumber } = require('ethers');
const { expect } = require('./shared/expect.js');
const RATE_SCALING_FACTOR = 10 ** 4;



describe('SecuritizationPool', () => {
  let setupTest;
  let stableCoin;
  let securitizationManagerContract

  // Wallets
  let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner;
  before('create fixture', async () => {
    [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner] = await ethers.getSigners();
    setupTest = deployments.createFixture(
      async ({ deployments, getNamedAccounts, ethers }, options) => {
        await deployments.fixture(); // ensure you start from a fresh deployments
        const tokenFactory = await ethers.getContractFactory('TestERC20');
        const stableCoin = (await tokenFactory.deploy('cUSD', 'cUSD', BigNumber.from(2).pow(255)));
        await stableCoin.transfer(lenderSigner.address, BigNumber.from(1000).pow(18)) // Lender has 1000$
        const { get } = deployments;
        securitizationManagerContract = await ethers.getContractAt(
          'SecuritizationManager',
          (await get('SecuritizationManager')).address,
        );

        return {
          stableCoin: stableCoin,
        };
      },
    );

  });
  beforeEach('deploy fixture', async () => {
    ({ stableCoin } = await setupTest());
  });

  describe('#setRiskScore', async () => {
    it('Should set risk score successfully', async function() {
      const { get } = deployments;

      const POOL_CREATOR_ROLE = await securitizationManagerContract.POOL_CREATOR();
      await securitizationManagerContract.grantRole(POOL_CREATOR_ROLE, poolCreatorSigner.address);
      // Create new pool
      const transaction = await securitizationManagerContract.connect(poolCreatorSigner).newPoolInstance(stableCoin.address, '100000');
      const receipt = await transaction.wait();
      const [securitizationPoolAddress] = receipt.events.find(e => e.event == 'NewPoolCreated').args;

      const securitizationPoolContract = await ethers.getContractAt('SecuritizationPool', securitizationPoolAddress);

      const daysPastDues = [86400, 2592000, 5184000, 7776000, 10368000, 31536000]
      const ratesAndDefaults = [950000, 900000, 910000, 800000, 810000, 0, 1500000, 1500000, 1500000, 1500000, 1500000, 1500000, 80000, 100000, 120000, 120000, 140000, 1000000, 10000, 20000, 30000, 40000, 50000, 1000000, 250000, 500000, 500000, 750000, 1000000, 1000000];
      const periodsAndWriteOffs = [432000, 432000, 432000, 432000, 432000, 432000, 2592000, 2592000, 2592000, 2592000, 2592000, 2592000, 250000, 500000, 500000, 750000, 1000000, 1000000, 1000000, 1000000, 1000000, 1000000, 1000000, 1000000]
      await securitizationPoolContract.connect(poolCreatorSigner).setupRiskScores(
        daysPastDues,
        ratesAndDefaults,
        periodsAndWriteOffs,
      );

      // TODO Check expect
    });

    it('only pool owner can setRiskScore', async function() {
    });

  });
  describe('#setPot', async () => {

  });
  describe('#collectAssets', async () => {

  });

  describe('#withdraw', async () => {

  });

  describe('#collectERC20Assets', async () => {

  });
  describe('#withdrawERC20Assets', async () => {

  });
  describe('#claimERC20Assets', async () => {

  });
  describe('#claimCashRemain', async () => {

  });
  describe('#injectTGEAddress', async () => {

  });
  describe('#startCycle', async () => {

  });
  describe('#setInterestRateForSOT', async () => {

  });
  describe('#increaseLockedDistributeBalance', async () => {

  });
  describe('#decreaseLockedDistributeBalance', async () => {

  });
  describe('#increaseTotalAssetRepaidCurrency', async () => {

  });
  describe('#redeem', async () => {

  });
  describe('#onBuyNoteToken', async () => {

  });
});
