const { expect } = require('chai');
const { networks } = require('../networks');

task('validate-contracts', 'Validate all contract infos').setAction(async (taskArgs, hre) => {
  const { deployments, ethers } = hre;
  const { get, read } = deployments;
  const [deployer] = await ethers.getSigners();

  const Registry = await ethers.getContractFactory('Registry');
  const registryContract = await get('Registry');
  const registry = await Registry.attach(registryContract.address);

  /**
   * Check Registry
   */
  const contracts = [
    'SecuritizationManager',
    'SecuritizationPool',
    'NoteTokenFactory',
    'NoteToken',
    'TokenGenerationEventFactory',
    'DistributionOperator',
    'DistributionAssessor',
    'DistributionTranche',
    'LoanAssetToken',
    'AcceptedInvoiceToken',
    'LoanRegistry',
    'LoanInterestTermsContract',
    'LoanRepaymentRouter',
    'LoanKernel',
    '',
    '',
    '',
    'SecuritizationPoolValueService',
    'MintedIncreasingInterestTGE',
    'MintedNormalTGE',
    '',
    '',
    '',
    '',
    '',
    'Go',
  ];

  for (let i = 0; i < contracts.length; i++) {
    const contract = contracts[i];

    if (!contract.length) {
      continue;
    }

    const contractDeployment = await get(contract);

    const component = await registry.getAddress(i);

    expect(contractDeployment.address).to.equal(component);
  }

  /**
   * Check UID
   */

  const uids = [0, 1, 2, 3];

  for (let i = 0; i < uids.length; i++) {
    const ui = await read('UniqueIdentity', 'supportedUIDTypes', uids[i]);
    expect(ui).to.equal(true);
  }

  for (let i = 0; i < uids.length; i++) {
    const smUI = await read('SecuritizationManager', 'allowedUIDTypes', uids[i]);
    expect(smUI.toString()).to.equal(uids[i].toString());
  }

  /**
   * Check KYC Admin Permission
   */

  const kycAdmin = network.config.kycAdmin;
  const OWNER_ROLE = await read('SecuritizationManager', 'OWNER_ROLE');
  const smRole = await read('SecuritizationManager', 'hasRole', OWNER_ROLE, kycAdmin);
  expect(smRole).to.equal(true);

  const SIGNER_ROLE = await read('UniqueIdentity', 'SIGNER_ROLE');
  const uiRole = await read('UniqueIdentity', 'hasRole', SIGNER_ROLE, kycAdmin);
  expect(uiRole).to.equal(true);
});
