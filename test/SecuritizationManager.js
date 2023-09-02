const { ethers} = require('hardhat');
const { deployments } = require('hardhat');
const { BigNumber } = require('ethers');
const { expect } = require('./shared/expect.js');
const RATE_SCALING_FACTOR = 10 ** 4;



describe('SecuritizationManager', () => {
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
  it('should emit RoleGranted event with an address', async function() {
    const POOL_CREATOR_ROLE = await securitizationManagerContract.POOL_CREATOR();
    const transaction = await securitizationManagerContract.grantRole(POOL_CREATOR_ROLE, poolCreatorSigner.address);
    await transaction.wait();
    await expect(transaction)
      .to.emit(securitizationManagerContract, "RoleGranted")
      .withArgs(POOL_CREATOR_ROLE, poolCreatorSigner.address, untangledAdminSigner.address);

  });
  describe('#newPoolInstance', async () => {
    it('Should create new pool instance', async function() {
      // await deployments.fixture();
      const { get } = deployments;

      //
      const POOL_CREATOR_ROLE = await securitizationManagerContract.POOL_CREATOR();
      await securitizationManagerContract.grantRole(POOL_CREATOR_ROLE, poolCreatorSigner.address);
      // Create new pool
      const minFirstLostCushion = 10 * RATE_SCALING_FACTOR;
      const transaction = await securitizationManagerContract.connect(poolCreatorSigner).newPoolInstance(
        stableCoin.address,
        minFirstLostCushion,
      );
      const receipt = await transaction.wait();
      const [SecuritizationPoolAddress] = receipt.events.find(e => e.event == 'NewPoolCreated').args;
      expect(SecuritizationPoolAddress).to.be.properAddress;
      const securitizationPoolContract = await ethers.getContractAt('SecuritizationPool', SecuritizationPoolAddress);

      expect(await securitizationPoolContract.underlyingCurrency()).to.equal(stableCoin.address);
      expect(await securitizationPoolContract.minFirstLossCushion()).to.equal(minFirstLostCushion);
      expect(await securitizationManagerContract.isExistingPools(SecuritizationPoolAddress)).to.equal(true);
      expect(await securitizationPoolContract.hasRole(await securitizationPoolContract.OWNER_ROLE(), poolCreatorSigner.address)).to.equal(true);
    });

    it('revert if minFistLossCushion >= 100%', async () => {
      // TODO Try create new pool with minFirstLossCushion >=100%
    })

    it('only pool creator role can create pool', async () => {
      // TODO Try create new pool by wallet which is not POOL_CREATOR role
    })

  });
  describe('#setUpTGEForSOT', async () => {

  });

  describe('#setUpTGEForJOT', async () => {

  });

  describe('#buyTokens', async () => {

  });
});