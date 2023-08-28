// const NoteToken = artifacts.require("NoteToken");
const Registry = artifacts.require("Registry");
const LoanKernel = artifacts.require("LoanKernel");
const LoanAssetToken = artifacts.require("LoanAssetToken");
const SecuritizationManager = artifacts.require("SecuritizationManager");
 
const SecuritizationPool = artifacts.require("SecuritizationPool");
const NoteTokenFactory = artifacts.require("NoteTokenFactory");
const TokenGenerationEventFactory = artifacts.require("TokenGenerationEventFactory");
module.exports = async function (deployer, accounts) {
  // console.log(4,) external override whenNotPaused nonReentrant onlySecuritizationManager returns (address) { accounts[1])
  await deployer.deploy(Registry);
  await deployer.deploy(SecuritizationManager);
  await deployer.deploy(LoanKernel);
  await deployer.deploy(LoanAssetToken);
 
  await deployer.deploy(SecuritizationPool);
  await deployer.deploy(NoteTokenFactory);
  await deployer.deploy(TokenGenerationEventFactory);
  
  
  const RegistryContract = await Registry.deployed();
  const SecuritizationManagerContract = await SecuritizationManager.deployed();
 
  const NoteTokenFactoryContract = await NoteTokenFactory.deployed();
  const TokenGenerationEventFactoryContract = await TokenGenerationEventFactory.deployed();
  const LoanKernelContract = await LoanKernel.deployed();
  const LoanAssetTokenContract = await LoanAssetToken.deployed();
  const SecuritizationPoolContract = await SecuritizationPool.deployed();
  console.log(11, RegistryContract.address)
  console.log(12, SecuritizationManagerContract.address)
};
