const { deployProxy } = require('../utils/deployHelper');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, execute, get, save } = deployments;
  const { deployer, invoiceOperator } = await getNamedAccounts();
  const registry = await get('Registry');

  //deploy InventoryLoanKernel
  const inventoryLoanKernelProxy = await deployProxy({ getNamedAccounts, deployments }, 'InventoryLoanKernel', [registry.address]);
  if (inventoryLoanKernelProxy.newlyDeployed) {
    await execute('Registry', { from: deployer, log: true }, 'setInventoryLoanKernel', inventoryLoanKernelProxy.address);
    await execute(
      'LoanAssetToken',
      { from: deployer, log: true },
      'grantRole',
      '0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6', // MINTER_ROLE
      inventoryLoanKernelProxy.address
    );
  }

  //deploy InventoryLoanRegistry
  const inventoryLoanRegistryProxy = await deployProxy({ getNamedAccounts, deployments }, 'InventoryLoanRegistry', [registry.address]);
  if (inventoryLoanRegistryProxy.newlyDeployed) {
    await execute('Registry', { from: deployer, log: true }, 'setInventoryLoanRegistry', inventoryLoanRegistryProxy.address);
  }

  //deploy LoanRepaymentRouter
  const inventoryLoanRepaymentRouterProxy = await deployProxy({ getNamedAccounts, deployments }, 'InventoryLoanRepaymentRouter', [
    registry.address,
  ]);
  if (inventoryLoanRepaymentRouterProxy.newlyDeployed) {
    await execute(
      'Registry',
      { from: deployer, log: true },
      'setInventoryLoanRepaymentRouter',
      inventoryLoanRepaymentRouterProxy.address
    );
  }

  //deploy InventoryLoanInterestTermsContract
  const inventoryLoanInterestTermsContractProxy = await deployProxy(
    { getNamedAccounts, deployments },
    'InventoryInterestTermsContract',
    [registry.address]
  );
  if (inventoryLoanInterestTermsContractProxy.newlyDeployed) {
    await execute(
      'Registry',
      { from: deployer, log: true },
      'setInventoryInterestTermsContract',
      inventoryLoanInterestTermsContractProxy.address
    );
  }

  //deploy InventoryCollateralizer
  const inventoryLoanCollateralizerProxy = await deployProxy(
    { getNamedAccounts, deployments },
    'InventoryCollateralizer',
    [registry.address]
  );
  if (inventoryLoanCollateralizerProxy.newlyDeployed) {
    await execute(
      'Registry',
      { from: deployer, log: true },
      'setInventoryCollateralizer',
      inventoryLoanCollateralizerProxy.address
    );
    await execute(
      'InventoryCollateralizer',
      { from: deployer, log: true },
      'grantRole',
      '0x19324e25c49f56fdb78b863d5665f337e7eac48caa2906dee9b87762239d739a', // COLLATERALIZER
      inventoryLoanInterestTermsContractProxy.address
    );
  }
};

module.exports.dependencies = ['registry'];
module.exports.tags = ['inventory_loan'];
