//deploy LoanKernel

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { get, execute, deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const registry = await get('Registry');

  const loanAssetToken = await deploy('LoanAssetToken', {
    from: deployer,
    proxy: {
      proxyContract: 'OpenZeppelinTransparentProxy',
      args: [registry.address, 'Loan Asset Token', 'LAT', ''],
    },
    log: true,
  });

  await execute('Registry', { from: deployer, log: true }, 'setLoanAssetToken', loanAssetToken.address);
};

module.exports.dependencies = ['Registry'];
module.exports.tags = ['next', 'mainnet', 'LoanAssetToken'];
