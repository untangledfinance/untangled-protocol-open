//deploy LoanKernel

const { deployProxy } = require('../../utils/deployHelper');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { get, execute, deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const registry = await get('Registry');

  const loanAssetToken = await deploy('LoanAssetToken', {
    from: deployer,
    args: [registry.address, 'Loan Asset Token', 'LAT', ''],
    proxy: {
      proxyContract: 'OpenZeppelinTransparentProxy',
    },
    log: true,
  });

  await execute('Registry', { from: deployer, log: true }, 'setLoanAssetToken', loanAssetToken.address);
};

module.exports.dependencies = ['registry'];
module.exports.tags = ['v4', 'mainnet', 'LoanAssetToken'];
