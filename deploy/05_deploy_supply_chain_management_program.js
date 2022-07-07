const { deployProxy } = require('../utils/deployHelper');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { get } = deployments;
  const registry = await get('Registry');

  //deploy SupplyChainManagementProgram
  const securitizationManagerProxy = await deployProxy({ getNamedAccounts, deployments }, 'SupplyChainManagementProgram', [
    registry.address
  ]);
};

module.exports.dependencies = ['registry'];
module.exports.tags = ['supply_chain'];
