const { ethers, upgrades } = require('hardhat');
const { deployments } = require('hardhat');
const { OWNER_ROLE, POOL_ADMIN_ROLE, VALIDATOR_ADMIN_ROLE } = require('./constants');

const { parseEther } = ethers.utils;


const setUpLoanAssetToken = async (registry, securitizationManager) => {
  const LoanAssetToken = await ethers.getContractFactory('LoanAssetToken');
  const loanAssetTokenContract = await upgrades.deployProxy(LoanAssetToken, [registry.address, 'TEST', 'TST', 'test.com'], {
    initializer: 'initialize(address,string,string,string)',
  });
  await registry.setLoanAssetToken(loanAssetTokenContract.address);

  const [poolAdmin, defaultLoanAssetTokenValidator] = await ethers.getSigners();

  await loanAssetTokenContract.grantRole(VALIDATOR_ADMIN_ROLE, securitizationManager.address);
  await securitizationManager.grantRole(OWNER_ROLE, poolAdmin.address);

  await securitizationManager.connect(poolAdmin).registerValidator(defaultLoanAssetTokenValidator.address);

  return {
    loanAssetTokenContract,
    defaultLoanAssetTokenValidator
  };
}

const setUpAcceptedInvoiceToken = async (registry) => {
  const AcceptedInvoiceToken = await ethers.getContractFactory('AcceptedInvoiceToken');
  const acceptedInvoiceToken = await upgrades.deployProxy(
    AcceptedInvoiceToken,
    [registry.address, 'TEST', 'TST', 'test.com'],
    {
      initializer: 'initialize(address,string,string,string)',
    }
  );

  return { acceptedInvoiceToken };
}

const setUpNoteTokenFactory = async (registry, factoryAdmin) => {
  const NoteTokenFactory = await ethers.getContractFactory('NoteTokenFactory');
  const noteTokenFactory = await upgrades.deployProxy(NoteTokenFactory, [registry.address, factoryAdmin.address]);

  const NoteToken = await ethers.getContractFactory('NoteToken');
  const noteTokenImpl = await NoteToken.deploy();
  // await registry.setNoteToken(noteTokenImpl.address);
  await noteTokenFactory.setNoteTokenImplementation(noteTokenImpl.address);

  return { noteTokenFactory };
}

async function setup() {
  await deployments.fixture(['all']);

  let stableCoin;
  let registry;

  let loanInterestTermsContract;
  let loanRegistry;
  let loanKernel;
  let loanRepaymentRouter;
  let securitizationManager;
  let securitizationPoolValueService;
  let go;
  let uniqueIdentity;
  let tokenGenerationEventFactory;
  let distributionAssessor;
  let distributionOperator;
  let distributionTranche;
  let factoryAdmin;

  const [untangledAdminSigner] = await ethers.getSigners();

  const tokenFactory = await ethers.getContractFactory('TestERC20');
  stableCoin = await tokenFactory.deploy('cUSD', 'cUSD', parseEther('100000'));

  const Registry = await ethers.getContractFactory('Registry');
  registry = await upgrades.deployProxy(Registry, []);

  const admin = await upgrades.admin.getInstance();

  factoryAdmin = await ethers.getContractAt('ProxyAdmin', admin.address);

  const SecuritizationManager = await ethers.getContractFactory('SecuritizationManager');
  securitizationManager = await upgrades.deployProxy(SecuritizationManager, [registry.address, factoryAdmin.address]);
  await securitizationManager.grantRole(POOL_ADMIN_ROLE, untangledAdminSigner.address);

  const SecuritizationPoolValueService = await ethers.getContractFactory('SecuritizationPoolValueService');
  securitizationPoolValueService = await upgrades.deployProxy(SecuritizationPoolValueService, [registry.address]);

  const { noteTokenFactory } = await setUpNoteTokenFactory(registry, factoryAdmin);

  const TokenGenerationEventFactory = await ethers.getContractFactory('TokenGenerationEventFactory');
  tokenGenerationEventFactory = await upgrades.deployProxy(TokenGenerationEventFactory, [
    registry.address,
    factoryAdmin.address,
  ]);

  const UniqueIdentity = await ethers.getContractFactory('UniqueIdentity');
  uniqueIdentity = await upgrades.deployProxy(UniqueIdentity, [untangledAdminSigner.address, '']);
  await uniqueIdentity.setSupportedUIDTypes([0, 1, 2, 3], [true, true, true, true]);
  await securitizationManager.setAllowedUIDTypes([0, 1, 2, 3]);

  const Go = await ethers.getContractFactory('Go');
  go = await upgrades.deployProxy(Go, [untangledAdminSigner.address, uniqueIdentity.address]);
  await registry.setGo(go.address);

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


  const { loanAssetTokenContract, defaultLoanAssetTokenValidator } = await setUpLoanAssetToken(registry, securitizationManager);

  const { acceptedInvoiceToken } = await setUpAcceptedInvoiceToken(registry);
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

  return {
    stableCoin,
    registry,
    loanAssetTokenContract,
    defaultLoanAssetTokenValidator,

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
