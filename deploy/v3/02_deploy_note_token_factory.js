const { getChainId } = require('hardhat');
const { registrySet } = require('./utils');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, execute, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const registry = await deployments.get('Registry');
  const proxyAdmin = await get('DefaultProxyAdmin');

  await deployments.deploy('NoteTokenFactory', {
    from: deployer,
    proxy: {
      proxyContract: 'OpenZeppelinTransparentProxy',
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
    },
    skipIfAlreadyDeployed: true,
    log: true,
  });

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

  const contracts = ['NoteTokenFactory'];
  await registrySet(contracts);
};

module.exports.dependencies = ['registry', 'note_token_impl'];
module.exports.tags = ['migration_mumbai', 'note_factory_mumbai_migration'];
