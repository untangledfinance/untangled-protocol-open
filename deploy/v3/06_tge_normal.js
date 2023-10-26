const { registrySet } = require('./utils');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { get, execute } = deployments;
  const { deployer } = await getNamedAccounts();

  const tgeNormal = await deployments.deploy('MintedNormalTGE', {
    from: deployer,
  });

  await execute('TokenGenerationEventFactory', {
    from: deployer,
    log: true,
  }, 'setTGEImplAddress', 1, tgeNormal.address);

  await execute('TokenGenerationEventFactory', {
    from: deployer,
    log: true,
  }, 'setTGEImplAddress', 2, tgeNormal.address);

};

module.exports.dependencies = ['registry', 'tge_factory'];
module.exports.tags = ['mainnet', 'tge_normal'];
