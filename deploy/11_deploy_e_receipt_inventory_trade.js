const { deployProxy } = require('../utils/deployHelper');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const {  get } = deployments;
  const registry = await get('Registry');

  //deploy EReceiptInventoryTradeFactory
  const eReceiptInventoryTradeFactoryProxy = await deployProxy({ getNamedAccounts, deployments }, 'EReceiptInventoryTradeFactory', [
    registry.address,
  ]);
};

module.exports.dependencies = ['registry'];
module.exports.tags = ['trade'];
