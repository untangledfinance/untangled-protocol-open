const { deployProxy } = require('../utils/deployHelper');

module.exports = async ({ getNamedAccounts, deployments }) => {
  //deploy SupplyChainManagementProgram
  await deployProxy({ getNamedAccounts, deployments }, 'TokenTopupController', []);
};

module.exports.tags = ['top_up'];
