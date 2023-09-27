const { getChainId } = require('hardhat');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { readDotFile, deploy, execute, get, save } = deployments;
  const { deployer } = await getNamedAccounts();

  await deployments.deploy('UntangledBridgeRouterV2', {
    from: deployer,
    skipIfAlreadyDeployed: true,
    log: true,
  });
};

module.exports.dependencies = [];
module.exports.tags = ['bridge_router_v2_multisig'];
