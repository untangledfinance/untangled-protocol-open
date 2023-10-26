const { registrySet } = require('./utils');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { get, execute } = deployments;
  const { deployer } = await getNamedAccounts();

  const tgeInterest = await deployments.deploy('MintedIncreasingInterestTGE', {
    from: deployer,
  });


  // MINTED_INCREASING_INTEREST_SOT,
  await execute('TokenGenerationEventFactory', {
    from: deployer,
    log: true,
  }, 'setTGEImplAddress', 0, tgeInterest.address);

};

module.exports.dependencies = ['registry', 'tge_factory'];
module.exports.tags = ['mainnet', 'tge_interest'];
