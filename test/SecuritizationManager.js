const { ethers } = require('hardhat');
const { deployments } = require('hardhat');
const { BigNumber } = require('ethers');
const { expect } = require('./shared/expect.js');

const { setup } = require('./setup.js');

const RATE_SCALING_FACTOR = 10 ** 4;

describe('SecuritizationManager', () => {
  let stableCoin;
  let securitizationManager;

  // Wallets
  let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner;
  before('create fixture', async () => {
    [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner] =
      await ethers.getSigners();

    ({ stableCoin, securitizationManager } = await setup());
  });

  it('should emit RoleGranted event with an address', async function () {
    // const POOL_CREATOR_ROLE = await securitizationManagerContract.POOL_CREATOR();
    // const transaction = await securitizationManagerContract.grantRole(POOL_CREATOR_ROLE, poolCreatorSigner.address);
    // await transaction.wait();
    // await expect(transaction)
    //   .to.emit(securitizationManagerContract, 'RoleGranted')
    //   .withArgs(POOL_CREATOR_ROLE, poolCreatorSigner.address, untangledAdminSigner.address);
  });
  describe('#newPoolInstance', async () => {
    it('Should create new pool instance', async function () {
      // // await deployments.fixture();
      // const { get } = deployments;
      // //
      // const POOL_CREATOR_ROLE = await securitizationManagerContract.POOL_CREATOR();
      // await securitizationManagerContract.grantRole(POOL_CREATOR_ROLE, poolCreatorSigner.address);
      // // Create new pool
      // const minFirstLostCushion = 10 * RATE_SCALING_FACTOR;
      // const transaction = await securitizationManagerContract
      //   .connect(poolCreatorSigner)
      //   .newPoolInstance(stableCoin.address, minFirstLostCushion);
      // const receipt = await transaction.wait();
      // const [SecuritizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;
      // expect(SecuritizationPoolAddress).to.be.properAddress;
      // const securitizationPoolContract = await ethers.getContractAt('SecuritizationPool', SecuritizationPoolAddress);
      // expect(await securitizationPoolContract.underlyingCurrency()).to.equal(stableCoin.address);
      // expect(await securitizationPoolContract.minFirstLossCushion()).to.equal(minFirstLostCushion);
      // expect(await securitizationManagerContract.isExistingPools(SecuritizationPoolAddress)).to.equal(true);
      // expect(
      //   await securitizationPoolContract.hasRole(
      //     await securitizationPoolContract.OWNER_ROLE(),
      //     poolCreatorSigner.address
      //   )
      // ).to.equal(true);
    });

    it('revert if minFistLossCushion >= 100%', async () => {
      // TODO Try create new pool with minFirstLossCushion >=100%
    });

    it('only pool creator role can create pool', async () => {
      // TODO Try create new pool by wallet which is not POOL_CREATOR role
    });
  });
  describe('#setUpTGEForSOT', async () => {});

  describe('#setUpTGEForJOT', async () => {});

  describe('#buyTokens', async () => {});
});
