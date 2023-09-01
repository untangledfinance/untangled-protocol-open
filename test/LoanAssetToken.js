const { ethers, upgrades } = require('hardhat');
const { deployments } = require('hardhat');
const { expect } = require('./shared/expect.js');

const { parseEther } = ethers.utils;

const { unlimitedAllowance } = require('./utils.js');

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

  // Wallets
  let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner;
  before('create fixture', async () => {
    [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner] =
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

      await securitizationPoolContract
        .connect(poolCreatorSigner)
        .setupRiskScores(
          [86400, 2592000, 5184000, 7776000, 10368000, 31536000],
          [
            950000, 900000, 910000, 800000, 810000, 0, 1500000, 1500000, 1500000, 1500000, 1500000, 1500000, 80000,
            100000, 120000, 120000, 140000, 1000000, 10000, 20000, 30000, 40000, 50000, 1000000, 250000, 500000, 500000,
            750000, 1000000, 1000000,
          ],
          [
            432000, 432000, 432000, 432000, 432000, 432000, 2592000, 2592000, 2592000, 2592000, 2592000, 2592000,
            250000, 500000, 500000, 750000, 1000000, 1000000, 1000000, 1000000, 1000000, 1000000, 1000000, 1000000,
          ]
        );
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
      const tokenIds = ['0x7580747133f5948462024dcfc5525f81020876c1725c2ea1a91740e2efb4421a'];

      await loanKernel.fillDebtOrder(
        [
          securitizationPoolContract.address,
          stableCoin.address,
          loanRepaymentRouter.address,
          loanInterestTermsContract.address,
          '0x5d99687F0d1F20C39EbBb4E9890999BEB7F754A5',
          '0x0000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000',
          '0x0000000000000000000000000000000000000000',
        ],
        [
          '0',
          '0',
          '456820000000000000',
          '365550000000000000',
          '350030000000000000',
          '118530000000000000',
          '385910000000000000',
          '100820000000000000',
          '280300000000000000',
          '193210000000000000',
          '164940000000000000',
          '248450000000000000',
          '262010000000000030',
          '221970000000000000',
          '191120000000000000',
        ],
        ['0x00000000000656f35ea24b40000186a010000000000000000000044700200000'],
        tokenIds
      );
    });
  });

  describe('#burn', async () => {
    it('No one than LoanKernel contract can burn', async () => {
      await expect(
        loanAssetTokenContract
          .connect(untangledAdminSigner)
          .burn('0x7580747133f5948462024dcfc5525f81020876c1725c2ea1a91740e2efb4421a')
      ).to.be.revertedWith(`ERC721: caller is not token owner or approved`);
    });

    it('only LoanKernel contract can burn', async () => {
      await loanRepaymentRouter
        .connect(untangledAdminSigner)
        .repayInBatch(
          ['0x7580747133f5948462024dcfc5525f81020876c1725c2ea1a91740e2efb4421a'],
          [parseEther('100')],
          stableCoin.address
        );
    });
  });
});
