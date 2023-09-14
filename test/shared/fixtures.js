const { deployments } = require('hardhat');
const { BigNumber } = require('ethers');

const mainFixture = deployments.createFixture(async ({ deployments, getNamedAccounts, ethers }, options) => {
  await deployments.fixture(); // ensure you start from a fresh deployments
  const { get } = deployments;

  const tokenFactory = await ethers.getContractFactory('TestERC20');
  const stableCoin = await tokenFactory.deploy('cUSD', 'cUSD', BigNumber.from(2).pow(255));
  const registryContract = await ethers.getContractAt('Registry', (await get('Registry')).address);
  const securitizationManagerContract = await ethers.getContractAt(
    'SecuritizationManager',
    (
      await get('SecuritizationManager')
    ).address,
  );
  const loanKernelContract = await ethers.getContractAt('LoanKernel', (await get('LoanKernel')).address);
  const loanRepaymentRouterContract = await ethers.getContractAt(
    'LoanRepaymentRouter',
    (
      await get('LoanRepaymentRouter')
    ).address,
  );
  const loanAssetTokenContract = await ethers.getContractAt('LoanAssetToken', (await get('LoanAssetToken')).address);
  const uniqueIdentityContract = await ethers.getContractAt('UniqueIdentity', (await get('UniqueIdentity')).address);
  const loanInterestTermsContract = await ethers.getContractAt('LoanInterestTermsContract', (await get('LoanInterestTermsContract')).address);
  const loanRegistryContract = await ethers.getContractAt('LoanRegistry', (await get('LoanRegistry')).address);
  const distributionOperatorContract = await ethers.getContractAt('DistributionOperator', (await get('DistributionOperator')).address);
  const distributionTrancheContract = await ethers.getContractAt('DistributionTranche', (await get('DistributionTranche')).address);
  const distributionAssessorContract = await ethers.getContractAt('DistributionAssessor', (await get('DistributionAssessor')).address);
  const securitizationPoolValueService = await ethers.getContractAt('SecuritizationPoolValueService', (await get('SecuritizationPoolValueService')).address);
  const goContract = await ethers.getContractAt('Go', (await get('Go')).address);
  return {
    stableCoin,
    loanKernelContract,
    registryContract,
    loanAssetTokenContract,
    loanInterestTermsContract,
    loanRegistryContract,
    loanRepaymentRouterContract,
    goContract,
    uniqueIdentityContract,
    distributionOperatorContract,
    distributionTrancheContract,
    distributionAssessorContract,
    securitizationManagerContract,
    securitizationPoolValueService
  };
});

module.exports = {
  mainFixture: mainFixture,
};

