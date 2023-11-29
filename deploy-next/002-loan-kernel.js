//deploy LoanKernel

const { deployProxy } = require('../../utils/deployHelper');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { get, execute, deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const registry = await get('Registry');

  const loanKernelProxy = await deploy('LoanKernel', {
    from: deployer,
    args: [registry],
    proxy: {
      proxyContract: 'OpenZeppelinTransparentProxy',
    },
    log: true,
  });

  await execute('Registry', { from: deployer, log: true }, 'setLoanKernel', loanKernelProxy.address);
};

module.exports.dependencies = ['Registry'];
module.exports.tags = ['next', 'mainnet', 'LoanKernel'];
