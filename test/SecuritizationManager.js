const { ethers, getNamedAccounts } = require('hardhat');
const { deployments } = require('hardhat');
const { BigNumber } = require('ethers');


describe('Token', () => {
  let setupTest;
  let tokenA;

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
        return {
          tokenA: tokenA,
        };
      },
    );

  });
  beforeEach('deploy fixture', async () => {
    ({ tokenA } = await setupTest());
  });
  it('testing 1', async function() {
    // await deployments.fixture();
    const { deployer } = await getNamedAccounts();
    const { deploy, execute, get, save } = deployments;

    // const TokenContract = await ethers.getContractAt('TestERC20', (await get('TestERC20')).address);
    /*
        console.log("Deploy", deployer);
        await tokenA.connect(untangledAdminSigner).transfer(borrowerSigner.address, '10000000000000000000')
        const result = await tokenA.balanceOf(borrowerSigner.address)
        console.log(result);
    */
  });
  it('testing 2', async function() {
    const { deployer } = await getNamedAccounts();
    const { deploy, execute, get, save } = deployments;

    const balance = await tokenA.balanceOf(lenderSigner.address);
    console.log(balance);
  });
});