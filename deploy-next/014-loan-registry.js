const { getChainId } = require('hardhat');
const { networks } = require('../../networks');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, execute, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const registry = await get('Registry');

  await deploy('LoanRegistry', {
    from: deployer,
    proxy: {
      proxyContract: 'OpenZeppelinTransparentProxy',
      execute: {
        methodName: 'initialize',
        args: [registry.address],
      },
    },
    skipIfAlreadyDeployed: true,
    log: true,
  });
};

module.exports.dependencies = ['Registry'];
module.exports.tags = ['mainnet', 'LoanRegistry', 'next'];
