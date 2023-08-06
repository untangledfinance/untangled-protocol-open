const { deployProxy } = require('../utils/deployHelper');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { get, execute } = deployments;
  const { deployer } = await getNamedAccounts();
  const registry = await get('Registry');

  //deploy SupplyChainManagementProgram
  // const supplyChainManagementProgram = await deployProxy({ getNamedAccounts, deployments }, 'SupplyChainManagementProgram', [
  //   registry.address
  // ]);
  // if (supplyChainManagementProgram.newlyDeployed) {
  //   await execute(
  //     'Registry',
  //     { from: deployer, log: true },
  //     'setSupplyChainManagementProgram',
  //     supplyChainManagementProgram.address
  //   );
  //   await execute(
  //     'SupplyChainManagementProgram',
  //     { from: deployer, log: true },
  //     'grantRole',
  //     '0xda2b0f370bd2974923a71e73c465a6368d3708f6b738cc46b9a1ac650e1de010',
  //     deployer
  //   );
  // }
};

module.exports.dependencies = ['registry'];
module.exports.tags = ['supply_chain'];
