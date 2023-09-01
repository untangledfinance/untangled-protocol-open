const { deployProxy } = require('../utils/deployHelper');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { execute } = deployments;
  const { deployer } = await getNamedAccounts();

  //deploy UniqueIdentity
  const uniqueIdentityProxy = await deployProxy({ getNamedAccounts, deployments }, 'UniqueIdentity', [
    deployer, ''
  ]);
  if (uniqueIdentityProxy.newlyDeployed) {
    await execute(
      'UniqueIdentity',
      { from: deployer, log: true },
      'setSupportedUIDTypes',
      [0, 1, 2],
      [true, true, true]
    );
  }
};

module.exports.tags = ['unique_identity'];
