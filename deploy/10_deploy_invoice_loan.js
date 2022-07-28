const { deployProxy } = require('../utils/deployHelper');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, execute, get, save } = deployments;
  const { deployer, invoiceOperator } = await getNamedAccounts();
  const registry = await get('Registry');

  //deploy InvoiceLoanKernel
  const invoiceLoanKernelProxy = await deployProxy({ getNamedAccounts, deployments }, 'InvoiceLoanKernel', [registry.address]);
  if (invoiceLoanKernelProxy.newlyDeployed) {
    await execute('Registry', { from: deployer, log: true }, 'setInvoiceLoanKernel', invoiceLoanKernelProxy.address);
    await execute(
      'LoanAssetToken',
      { from: deployer, log: true },
      'grantRole',
      '0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6', // MINTER_ROLE
      invoiceLoanKernelProxy.address
    );
  }

  //deploy InvoiceDebtRegistry
  const invoiceLoanRegistryProxy = await deployProxy({ getNamedAccounts, deployments }, 'InvoiceDebtRegistry', [registry.address]);
  if (invoiceLoanRegistryProxy.newlyDeployed) {
    await execute('Registry', { from: deployer, log: true }, 'setInvoiceDebtRegistry', invoiceLoanRegistryProxy.address);
  }

  //deploy InvoiceLoanRepaymentRouter
  const invoiceLoanRepaymentRouterProxy = await deployProxy({ getNamedAccounts, deployments }, 'InvoiceLoanRepaymentRouter', [
    registry.address,
  ]);
  if (invoiceLoanRepaymentRouterProxy.newlyDeployed) {
    await execute(
      'Registry',
      { from: deployer, log: true },
      'setInvoiceLoanRepaymentRouter',
      invoiceLoanRepaymentRouterProxy.address
    );
  }

  //deploy InvoiceFinanceInterestTermsContract
  const invoiceLoanInterestTermsContractProxy = await deployProxy(
    { getNamedAccounts, deployments },
    'InvoiceFinanceInterestTermsContract',
    [registry.address]
  );
  if (invoiceLoanInterestTermsContractProxy.newlyDeployed) {
    await execute(
      'Registry',
      { from: deployer, log: true },
      'setInvoiceFinanceInterestTermsContract',
      invoiceLoanInterestTermsContractProxy.address
    );
  }

  //deploy InvoiceCollateralizer
  const invoiceLoanCollateralizerProxy = await deployProxy(
    { getNamedAccounts, deployments },
    'InvoiceCollateralizer',
    [registry.address]
  );
  if (invoiceLoanCollateralizerProxy.newlyDeployed) {
    await execute(
      'Registry',
      { from: deployer, log: true },
      'setInvoiceCollateralizer',
      invoiceLoanCollateralizerProxy.address
    );
    await execute(
      'InvoiceCollateralizer',
      { from: deployer, log: true },
      'grantRole',
      '0x19324e25c49f56fdb78b863d5665f337e7eac48caa2906dee9b87762239d739a', // COLLATERALIZER
      invoiceLoanInterestTermsContractProxy.address
    );
  }
};

module.exports.dependencies = ['registry'];
module.exports.tags = ['invoice_loan'];
