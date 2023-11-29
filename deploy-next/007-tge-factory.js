
module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, get, execute, read } = deployments;
  const { deployer } = await getNamedAccounts();

  await deploy('TokenGenerationEventFactory', {
    from: deployer,
    proxy: {
      // execute: {
      //   onUpgrade: {
      //     methodName: 'initializeV7',
      //     args: [registry.address, proxyAdmin.address],
      //   },
      // },
      proxyContract: "OpenZeppelinTransparentProxy",
    },
    log: true,
  });

  await execute('Registry', { from: deployer, log: true }, 'setTokenGenerationEventFactory', TokenGenerationEventFactory.address);

  // if (currentVersion.toNumber() < 94) {

  // await execute('TokenGenerationEventFactory', {
  //     from: deployer,
  //     log: true,
  //   }, 'initialize', registry.address, proxyAdmin.address);
  //   // }

  // await registrySet(['TokenGenerationEventFactory']);
};

module.exports.dependencies = ['Registry'];
module.exports.tags = ['next', 'mainnet', 'TokenGenerationEventFactory'];
