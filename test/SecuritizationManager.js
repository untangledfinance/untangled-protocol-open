const { ethers} = require('hardhat');
const { deployments } = require('hardhat');
const { BigNumber } = require('ethers');
const { expect } = require('./shared/expect.js');



describe('SecuritizationManager', () => {
  let setupTest;
  let tokenA;
  let securitizationManagerContract

  // Wallets
  let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner;
  before('create fixture', async () => {
    [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner] = await ethers.getSigners();
    setupTest = deployments.createFixture(
      async ({ deployments, getNamedAccounts, ethers }, options) => {
        await deployments.fixture(); // ensure you start from a fresh deployments
        const tokenFactory = await ethers.getContractFactory('TestERC20');
        const tokenA = (await tokenFactory.deploy('cUSD', 'cUSD', BigNumber.from(2).pow(255)));
        await tokenA.transfer(lenderSigner.address, BigNumber.from(1000).pow(18)) // Lender has 1000$
        const { get } = deployments;
        securitizationManagerContract = await ethers.getContractAt(
          'SecuritizationManager',
          (await get('SecuritizationManager')).address,
        );

        return {
          tokenA: tokenA,
        };
      },
    );

  });
  beforeEach('deploy fixture', async () => {
    ({ tokenA } = await setupTest());
  });
  it('Should create new pool instance', async function() {
    // await deployments.fixture();
    const { get } = deployments;

    //
    const POOL_CREATOR_ROLE = await securitizationManagerContract.POOL_CREATOR();
    await securitizationManagerContract.grantRole(POOL_CREATOR_ROLE, poolCreatorSigner.address);
    // Create new pool
    const transaction = await securitizationManagerContract.connect(poolCreatorSigner).newPoolInstance(tokenA.address, '100000')
    const receipt = await transaction.wait();
    const [SecuritizationPoolAddress] = receipt.events.find(e => e.event == 'NewPoolCreated').args;
    expect(SecuritizationPoolAddress).to.be.properAddress;
  });
  it('should emit RoleGranted event with an address', async function() {
    const POOL_CREATOR_ROLE = await securitizationManagerContract.POOL_CREATOR();
    const transaction = await securitizationManagerContract.grantRole(POOL_CREATOR_ROLE, poolCreatorSigner.address);
    await transaction.wait();
    await expect(transaction)
      .to.emit(securitizationManagerContract, "RoleGranted")
      .withArgs(POOL_CREATOR_ROLE, poolCreatorSigner.address, untangledAdminSigner.address);

  });
});
