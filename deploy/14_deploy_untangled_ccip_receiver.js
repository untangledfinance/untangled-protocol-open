const { getChainId } = require('hardhat');
const { deployProxy } = require('../utils/deployHelper');
const { networks } = require('../networks');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { readDotFile, deploy, execute, get, save } = deployments;

  console.log(network);
};

module.exports.dependencies = [];
module.exports.tags = ['untangled_ccip_receiver'];
