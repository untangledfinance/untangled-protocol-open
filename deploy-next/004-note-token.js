const { getChainId } = require('hardhat');
const { registrySet } = require('./utils');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, get, execute } = deployments;
  const { deployer } = await getNamedAccounts();

  const NoteToken = await get('NoteToken');
  await execute(
    'NoteTokenFactory',
    {
      from: deployer,
      log: true,
    },
    `setNoteTokenImplementation`,
    NoteToken.address,
  );
};

module.exports.dependencies = ['Registry', 'NoteTokenFactory'];
module.exports.tags = ['next', 'mainnet', 'NoteToken'];
