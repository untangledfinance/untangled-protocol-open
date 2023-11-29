const { getChainId } = require('hardhat');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deployer } = await getNamedAccounts();
  const { deploy } = deployments;

  await deploy('Registry', {
    from: deployer,
    proxy: {
      proxyContract: 'OpenZeppelinTransparentProxy',
    },
    log: true,
  });
};

module.exports.dependencies = [];
module.exports.tags = ['next', 'mainnet', 'Registry'];
