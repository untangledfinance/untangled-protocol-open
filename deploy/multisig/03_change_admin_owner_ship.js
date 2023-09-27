const { getChainId } = require('hardhat');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { readDotFile, deploy, execute, get, save } = deployments;
  const { deployer } = await getNamedAccounts();

  const bridgeRouterProxy = await deployments.get('UntangledBridgeRouter');

  console.log(bridgeRouterProxy);
};

module.exports.dependencies = [];
module.exports.tags = ['change_admin_multisig'];
