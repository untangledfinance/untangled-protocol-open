const { getChainId } = require('hardhat');
const { deployProxy } = require('../utils/deployHelper');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { readDotFile } = deployments;

  const router = await readDotFile('.CHAINLINK_CCIP_ROUTER');
  const untangledReceiver = await deployProxy({ getNamedAccounts, deployments }, 'UntangledReceiver', [
    router
  ]);

  if (untangledReceiver.newlyDeployed) {
    // setup action ...
    
  }
};

module.exports.dependencies = [];
module.exports.tags = ['untangled_ccip_receiver', 'core'];
