const { deployProxy } = require('../utils/deployHelper');
// console.log(2, "Securitization")
module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, execute, get, save } = deployments;
  const { deployer } = await getNamedAccounts();
  const registry = await get('Registry');

  //deploy SecuritizationManager
  const securitizationManagerProxy = await deployProxy({ getNamedAccounts, deployments }, 'SecuritizationManager', [
    registry.address,
  ]);
  if (securitizationManagerProxy.newlyDeployed) {
    await execute(
      'Registry',
      { from: deployer, log: true },
      'setSecuritizationManager',
      securitizationManagerProxy.address
    );
  }

  //deploy SecuritizationPool
  const poolImpl = await deploy(`SecuritizationPoolImpl`, {
    contract: 'SecuritizationPool',
    skipIfAlreadyDeployed: true,
    from: deployer,
    args: [],
    log: true,
  });
  if (poolImpl.newlyDeployed) {
    const POOL_IMPLEMENTATION_ADDRESS = poolImpl.address
    const pool = poolImpl;
    pool.address = poolImpl.address;
    await save('SecuritizationPool', pool);
    await execute('Registry', { from: deployer, log: true }, 'setSecuritizationPool', POOL_IMPLEMENTATION_ADDRESS);
  }

  //deploy SecuritizationPoolValueService
  const securitizationPoolValueServiceProxy = await deployProxy(
    { getNamedAccounts, deployments },
    'SecuritizationPoolValueService',
    [registry.address]
  );
  if (securitizationPoolValueServiceProxy.newlyDeployed) {
    await execute(
      'Registry',
      { from: deployer, log: true },
      'setSecuritizationPoolValueService',
      securitizationPoolValueServiceProxy.address
    );
  }
  console.log(51, securitizationPoolValueServiceProxy.address)
  //deploy NoteTokenFactory
  const noteTokenFactoryProxy = await deployProxy({ getNamedAccounts, deployments }, 'NoteTokenFactory', [
    registry.address,
  ]);
  if (noteTokenFactoryProxy.newlyDeployed) {
    await execute('Registry', { from: deployer, log: true }, 'setNoteTokenFactory', noteTokenFactoryProxy.address);
  }

  //deploy DistributionTranche
  const distributionTrancheProxy = await deployProxy({ getNamedAccounts, deployments }, 'DistributionTranche', [
    registry.address,
  ]);
  if (distributionTrancheProxy.newlyDeployed) {
    await execute(
      'Registry',
      { from: deployer, log: true },
      'setDistributionTranche',
      distributionTrancheProxy.address
    );
  }

  //deploy DistributionAssessor
  const distributionAssessorProxy = await deployProxy({ getNamedAccounts, deployments }, 'DistributionAssessor', [
    registry.address,
  ]);
  if (distributionAssessorProxy.newlyDeployed) {
    await execute(
      'Registry',
      { from: deployer, log: true },
      'setDistributionAssessor',
      distributionAssessorProxy.address
    );
  }

  //deploy DistributionOperator
  const distributionOperatorProxy = await deployProxy({ getNamedAccounts, deployments }, 'DistributionOperator', [
    registry.address,
  ]);
  if (distributionOperatorProxy.newlyDeployed) {
    await execute(
      'Registry',
      { from: deployer, log: true },
      'setDistributionOperator',
      distributionOperatorProxy.address
    );
  }
};

module.exports.dependencies = ['registry'];
module.exports.tags = ['pool'];
