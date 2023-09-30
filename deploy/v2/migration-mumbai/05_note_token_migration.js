const { getChainId } = require('hardhat');
const { registrySet } = require('../utils');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  await deploy('NoteToken', {
    from: deployer,
    skipIfAlreadyDeployed: true,
    args: [],
    log: true,
  });

  const contracts = ['NoteToken'];

  await registrySet(contracts);
};

module.exports.dependencies = ['registry', 'securitization_manager', 'note_token_factory'];
module.exports.tags = ['migration_mumbai', 'note_token_impl_mumbai_migration'];
