const { registrySet } = require('./utils');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, get, execute } = deployments;
  const { deployer } = await getNamedAccounts();

  const registry = await deployments.get('Registry');
  const proxyAdmin = await get('DefaultProxyAdmin');

  await deployments.deploy('TokenGenerationEventFactory', {
    from: deployer,
    proxy: {
      execute: {
        init: {
          methodName: 'initialize',
          args: [registry.address, proxyAdmin.address],
        },
        onUpgrade: {
          methodName: 'initialize',
          args: [registry.address, proxyAdmin.address],
        },
      },
      proxyContract: "OpenZeppelinTransparentProxy",
    }
  });

  const tgeInterest = await get('MintedIncreasingInterestTGE');
  const tgeNormal = await get('MintedNormalTGE');

  // MINTED_INCREASING_INTEREST_SOT,
  // NORMAL_SALE_JOT,
  // NORMAL_SALE_SOT
  await execute('TokenGenerationEventFactory', {
    from: deployer,
    log: true,
  }, 'setTGEImplAddress', 0, tgeInterest.address);

  await execute('TokenGenerationEventFactory', {
    from: deployer,
    log: true,
  }, 'setTGEImplAddress', 1, tgeNormal.address);

  await execute('TokenGenerationEventFactory', {
    from: deployer,
    log: true,
  }, 'setTGEImplAddress', 2, tgeNormal.address);

};

module.exports.dependencies = ['registry'];
module.exports.tags = ['mainnet', 'tge_factory'];
