const { deployProxy } = require('../utils/deployHelper');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deployer } = await getNamedAccounts();

  //deploy UniqueIdentity
  console.log("DEPLOYER", deployer);
  const uniqueIdentityProxy = await deployProxy({ getNamedAccounts, deployments }, 'UniqueIdentity', [
    deployer, ''
  ]);
};

module.exports.tags = ['unique_identity'];
