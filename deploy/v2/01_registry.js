const { getChainId } = require('hardhat');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  await deployments.deploy('Registry', {
    from: deployer,
    proxy: {
      proxyContract: 'OpenZeppelinTransparentProxy',
      execute: {
        methodName: 'initialize',
        args: [],
      },
    },
    log: true,
  });
};

module.exports.dependencies = [];
module.exports.tags = ['mainnet', 'registry'];
