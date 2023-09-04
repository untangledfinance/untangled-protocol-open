const { ethers, upgrades } = require('hardhat');
const { deployments } = require('hardhat');

const { parseEther } = ethers.utils;

async function setup() {
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

  const tokenFactory = await ethers.getContractFactory('TestERC20');
  stableCoin = await tokenFactory.deploy('cUSD', 'cUSD', parseEther('100000'));

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

  return {
    stableCoin,
    registry,
    loanAssetTokenContract,
    loanInterestTermsContract,
    loanRegistry,
    loanKernel,
    loanRepaymentRouter,
    securitizationManager,
    securitizationPoolContract,
    securitizationPoolValueService,
    securitizationPoolImpl,
  };
}

module.exports = {
  setup,
};
