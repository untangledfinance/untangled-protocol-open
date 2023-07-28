const NoteToken = artifacts.require("NoteToken");
const Registry = artifacts.require("Registry");
const LoanKernel = artifacts.require("LoanKernel");
const LoanAssetToken = artifacts.require("LoanAssetToken");
const SecuritizationManager = artifacts.require("SecuritizationManager");
 
const SecuritizationPool = artifacts.require("SecuritizationPool");
const NoteTokenFactory = artifacts.require("NoteTokenFactory");
 
const TokenGenerationEventFactory = artifacts.require("TokenGenerationEventFactory");
const DistributionAssessor = artifacts.require("DistributionAssessor");

const SecuritizationPoolValueService = artifacts.require("SecuritizationPoolValueService");

module.exports = async function (deployer, accounts) {
  // console.log(4,) external override whenNotPaused nonReentrant onlySecuritizationManager returns (address) { accounts[1])
  await deployer.deploy(Registry);
  await deployer.deploy(SecuritizationManager);
  await deployer.deploy(LoanKernel);
  await deployer.deploy(LoanAssetToken);
 
  const pool = await deployer.deploy(SecuritizationPool);
  console.log(23, pool.address)
  await deployer.deploy(NoteTokenFactory);
  await deployer.deploy(NoteToken,"Test", "TST", 18, pool.address, 1);
  await deployer.deploy(TokenGenerationEventFactory);

  
  await deployer.deploy(DistributionAssessor);
  await deployer.deploy(SecuritizationPoolValueService);
  const RegistryContract = await Registry.deployed();
  const SecuritizationManagerContract = await SecuritizationManager.deployed();
 
  const NoteTokenFactoryContract = await NoteTokenFactory.deployed();
  const TokenGenerationEventFactoryContract = await TokenGenerationEventFactory.deployed();
  const LoanKernelContract = await LoanKernel.deployed();
  const LoanAssetTokenContract = await LoanAssetToken.deployed();
  const SecuritizationPoolContract = await SecuritizationPool.deployed();
  const DistributionAssessorContract = await DistributionAssessor.deployed();
  const SecuritizationPoolValueServiceContract = await SecuritizationPoolValueService.deployed();
  const noteToken = await NoteToken.deployed();
  console.log(11, RegistryContract.address)
  console.log(12, SecuritizationManagerContract.address)
};
