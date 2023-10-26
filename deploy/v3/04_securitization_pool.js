const { registrySet } = require('./utils');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, get } = deployments;
  const { deployer } = await getNamedAccounts();

  await deployments.deploy('SecuritizationPool', {
    from: deployer,
  });

  await registrySet(['SecuritizationPool']);
};

module.exports.dependencies = ['registry'];
module.exports.tags = ['mainnet', 'securitization_pool'];
