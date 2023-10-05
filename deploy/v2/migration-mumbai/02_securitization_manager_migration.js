const { getChainId } = require('hardhat');
const { registrySet } = require('../utils');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, execute, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const registry = await deployments.get('Registry');
  const proxyAdmin = await get('DefaultProxyAdmin');

  await deployments.deploy('SecuritizationManager', {
    from: deployer,
    proxy: {
      proxyContract: 'OpenZeppelinTransparentProxy',
      execute: {
        methodName: 'initialize',
        args: [registry.address, proxyAdmin.address],
      },
    },
    skipIfAlreadyDeployed: true,
    log: true,
  });

  const contracts = ['SecuritizationManager'];

  await registrySet(contracts);
};

module.exports.dependencies = ['registry'];
module.exports.tags = ['migration_mumbai', 'securitization_manager_mumbai_migration'];
