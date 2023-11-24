const { getChainId } = require('hardhat');
const { networks } = require('../../networks');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, execute, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const registry = await deployments.get('Registry');

  const deployResult = await deployments.deploy('DistributionOperator', {
    from: deployer,
    proxy: {
      proxyContract: 'OpenZeppelinTransparentProxy',
      execute: {
        methodName: 'initialize',
        args: [registry.address],
      },
    },
    skipIfAlreadyDeployed: true,
    log: true,
  });

  await execute('Registry', { from: deployer, log: true }, 'setDistributionOperator', deployResult.address);
};

module.exports.dependencies = ['registry'];
module.exports.tags = ['mainnet', 'DistributionOperator', 'v3'];
