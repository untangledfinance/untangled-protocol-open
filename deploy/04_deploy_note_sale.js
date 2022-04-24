const { deployProxy } = require('../utils/deployHelper');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, execute, get, save } = deployments;
  const { deployer } = await getNamedAccounts();
  const registry = await get('Registry');

  //deploy MintedIncreasingInterestTGE
  const mintedIncreasingInterestTGEImpl = await deploy(`MintedIncreasingInterestTGEImpl`, {
    contract: 'MintedIncreasingInterestTGE',
    skipIfAlreadyDeployed: true,
    from: deployer,
    args: [],
    log: true,
  });
  const mintedIncreasingInterestTGEProxy = await deploy(`MintedIncreasingInterestTGEProxy`, {
    contract: 'UpgradableProxy',
    skipIfAlreadyDeployed: true,
    from: deployer,
    args: [mintedIncreasingInterestTGEImpl.address],
    log: true,
  });
  if (mintedIncreasingInterestTGEProxy.newlyDeployed) {
    const mintedIncreasingInterestTGE = mintedIncreasingInterestTGEImpl;
    mintedIncreasingInterestTGE.address = mintedIncreasingInterestTGEProxy.address;
    await save('MintedIncreasingInterestTGE', mintedIncreasingInterestTGE);
    await execute(
      'Registry',
      { from: deployer, log: true },
      'setMintedIncreasingInterestTGE',
      mintedIncreasingInterestTGEProxy.address
    );
  }

  //deploy TokenGenerationEventFactory
  const tokenGenerationEventFactoryProxy = await deployProxy(
    { getNamedAccounts, deployments },
    'TokenGenerationEventFactory',
    [registry.address]
  );
  if (tokenGenerationEventFactoryProxy.newlyDeployed) {
    await execute(
      'Registry',
      { from: deployer, log: true },
      'setTokenGenerationEventFactory',
      tokenGenerationEventFactoryProxy.address
    );
  }
};

module.exports.dependencies = ['registry'];
module.exports.tags = ['sale'];
