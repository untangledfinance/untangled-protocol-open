const { deployProxy } = require('../utils/deployHelper');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { execute, get } = deployments;
  const { deployer } = await getNamedAccounts();
  const supplyChainManagementProgram = await get('SupplyChainManagementProgram');

  //deploy CollateralManagementToken
  const collateralManagementTokenProxy = await deployProxy(
    { getNamedAccounts, deployments },
    'CollateralManagementToken',
    [supplyChainManagementProgram.address, "CMA Token", "CMA", 2, ''],
    'initialize(address,string,string,uint8,string)',
  );
  if (collateralManagementTokenProxy.newlyDeployed) {
    await execute('Registry', { from: deployer, log: true }, 'setCollateralManagementToken', collateralManagementTokenProxy.address);
  }

};

module.exports.dependencies = ['registry', 'supply_chain'];
module.exports.tags = ['cma'];
