const { getChainId } = require('hardhat');
const { registrySet } = require('./utils');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  await deploy('NoteToken', {
    from: deployer,
    skipIfAlreadyDeployed: true,
    args: [],
    log: true,
  });
  
};

module.exports.dependencies = ['registry', 'securitization_manager', 'note_token_factory'];
module.exports.tags = ['mainnet', 'note_token_impl'];
