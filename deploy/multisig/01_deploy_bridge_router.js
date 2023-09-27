const { getChainId } = require('hardhat');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { readDotFile, deploy, execute, get, save } = deployments;
  const { deployer } = await getNamedAccounts();

  await deployments.deploy('UntangledBridgeRouter', {
    from: deployer,
    proxy: {
      proxyContract: 'OpenZeppelinTransparentProxy',
      execute: {
        methodName: 'initialize',
        args: [deployer],
      },
    },
    skipIfAlreadyDeployed: true,
    log: true,
  });
};

module.exports.dependencies = [];
module.exports.tags = ['bridge_router_multisig'];
