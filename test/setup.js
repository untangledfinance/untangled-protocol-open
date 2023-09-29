const { ethers, upgrades } = require('hardhat');
const { deployments } = require('hardhat');

const { parseEther } = ethers.utils;

async function setup() {
  await deployments.fixture(['all']);

  let stableCoin;
  let registry;
  let loanAssetTokenContract;
  let loanInterestTermsContract;
  let loanRegistry;
  let loanKernel;
  let loanRepaymentRouter;
  let securitizationManager;
  let securitizationPoolValueService;
  let go;
  let uniqueIdentity;
  let noteTokenFactory;
  let tokenGenerationEventFactory;
  let distributionAssessor;
  let distributionOperator;
  let distributionTranche;
  let acceptedInvoiceToken;
  let factoryAdmin;

  const [untangledAdminSigner] = await ethers.getSigners();

  const tokenFactory = await ethers.getContractFactory('TestERC20');
  stableCoin = await tokenFactory.deploy('cUSD', 'cUSD', parseEther('100000'));

  const Registry = await ethers.getContractFactory('Registry');
  registry = await upgrades.deployProxy(Registry, []);

  const FactoryAdmin = await ethers.getContractFactory('FactoryAdmin');
  factoryAdmin = await upgrades.deployProxy(FactoryAdmin, []);

  const SecuritizationManager = await ethers.getContractFactory('SecuritizationManager');
  securitizationManager = await upgrades.deployProxy(SecuritizationManager, [registry.address, factoryAdmin.address]);
  const SecuritizationPoolValueService = await ethers.getContractFactory('SecuritizationPoolValueService');
  securitizationPoolValueService = await upgrades.deployProxy(SecuritizationPoolValueService, [registry.address]);

  const NoteTokenFactory = await ethers.getContractFactory('NoteTokenFactory');
  noteTokenFactory = await upgrades.deployProxy(NoteTokenFactory, [registry.address]);
  const TokenGenerationEventFactory = await ethers.getContractFactory('TokenGenerationEventFactory');
  tokenGenerationEventFactory = await upgrades.deployProxy(TokenGenerationEventFactory, [registry.address]);

  const UniqueIdentity = await ethers.getContractFactory('UniqueIdentity');
  uniqueIdentity = await upgrades.deployProxy(UniqueIdentity, [untangledAdminSigner.address, '']);
  await uniqueIdentity.setSupportedUIDTypes([0, 1, 2, 3], [true, true, true, true]);
  await securitizationManager.setAllowedUIDTypes([0, 1, 2, 3]);

  const Go = await ethers.getContractFactory('Go');
  go = await upgrades.deployProxy(Go, [untangledAdminSigner.address, uniqueIdentity.address]);

  const LoanInterestTermsContract = await ethers.getContractFactory('LoanInterestTermsContract');
  loanInterestTermsContract = await upgrades.deployProxy(LoanInterestTermsContract, [registry.address]);
  const LoanRegistry = await ethers.getContractFactory('LoanRegistry');
  loanRegistry = await upgrades.deployProxy(LoanRegistry, [registry.address]);
  const LoanKernel = await ethers.getContractFactory('LoanKernel');
  loanKernel = await upgrades.deployProxy(LoanKernel, [registry.address]);
  const LoanRepaymentRouter = await ethers.getContractFactory('LoanRepaymentRouter');
  loanRepaymentRouter = await upgrades.deployProxy(LoanRepaymentRouter, [registry.address]);
  const DistributionAssessor = await ethers.getContractFactory('DistributionAssessor');
  distributionAssessor = await upgrades.deployProxy(DistributionAssessor, [registry.address]);
  const DistributionOperator = await ethers.getContractFactory('DistributionOperator');
  distributionOperator = await upgrades.deployProxy(DistributionOperator, [registry.address]);
  const DistributionTranche = await ethers.getContractFactory('DistributionTranche');
  distributionTranche = await upgrades.deployProxy(DistributionTranche, [registry.address]);

  await registry.setLoanInterestTermsContract(loanInterestTermsContract.address);
  await registry.setLoanRegistry(loanRegistry.address);
  await registry.setLoanKernel(loanKernel.address);
  await registry.setLoanRepaymentRouter(loanRepaymentRouter.address);
  await registry.setSecuritizationPoolValueService(securitizationPoolValueService.address);
  await registry.setDistributionAssessor(distributionAssessor.address);
  await registry.setDistributionOperator(distributionOperator.address);
  await registry.setDistributionTranche(distributionTranche.address);

  const LoanAssetToken = await ethers.getContractFactory('LoanAssetToken');
  loanAssetTokenContract = await upgrades.deployProxy(LoanAssetToken, [registry.address, 'TEST', 'TST', 'test.com'], {
    initializer: 'initialize(address,string,string,string)',
  });

  const AcceptedInvoiceToken = await ethers.getContractFactory('AcceptedInvoiceToken');
  acceptedInvoiceToken = await upgrades.deployProxy(
    AcceptedInvoiceToken,
    [registry.address, 'TEST', 'TST', 'test.com'],
    {
      initializer: 'initialize(address,string,string,string)',
    }
  );

  await registry.setLoanAssetToken(loanAssetTokenContract.address);
  await registry.setAcceptedInvoiceToken(acceptedInvoiceToken.address);

  const SecuritizationPool = await ethers.getContractFactory('SecuritizationPool');
  const securitizationPoolImpl = await SecuritizationPool.deploy();
  const MintedIncreasingInterestTGE = await ethers.getContractFactory('MintedIncreasingInterestTGE');
  const mintedIncreasingInterestTGEImpl = await MintedIncreasingInterestTGE.deploy();
  const MintedNormalTGE = await ethers.getContractFactory('MintedNormalTGE');
  const mintedNormalTGEImpl = await MintedNormalTGE.deploy();

  await registry.setSecuritizationPool(securitizationPoolImpl.address);
  await registry.setSecuritizationManager(securitizationManager.address);
  await registry.setMintedIncreasingInterestTGE(mintedIncreasingInterestTGEImpl.address);
  await registry.setMintedNormalTGE(mintedNormalTGEImpl.address);

  await registry.setNoteTokenFactory(noteTokenFactory.address);
  await registry.setTokenGenerationEventFactory(tokenGenerationEventFactory.address);

  await registry.setGo(go.address);

  return {
    stableCoin,
    registry,
    loanAssetTokenContract,
    acceptedInvoiceToken,
    loanInterestTermsContract,
    loanRegistry,
    loanKernel,
    loanRepaymentRouter,
    securitizationManager,
    securitizationPoolValueService,
    securitizationPoolImpl,
    go,
    uniqueIdentity,
    noteTokenFactory,
    tokenGenerationEventFactory,
    distributionOperator,
    distributionAssessor,
    distributionTranche,
    factoryAdmin,
  };
}

module.exports = {
  setup,
};
