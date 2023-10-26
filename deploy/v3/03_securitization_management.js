const { getChainId } = require('hardhat');
const { registrySet } = require('./utils');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, get } = deployments;
  const { deployer } = await getNamedAccounts();
  const proxyAdmin = await get('DefaultProxyAdmin');

  const registry = await get("Registry");

  await deployments.deploy('SecuritizationManager', {
    from: deployer,

    proxy: {
      execute: {
        init: {
          methodName: 'initialize',
          args: [registry.address, proxyAdmin.address],
        },
        onUpgrade: {
          methodName: 'initialize',
          args: [registry.address, proxyAdmin.address],
        },
      },
      proxyContract: "OpenZeppelinTransparentProxy",
    }
  });

  await registrySet(['SecuritizationManager']);
};

module.exports.dependencies = ['registry'];
module.exports.tags = ['mainnet', 'securitization_manager'];
