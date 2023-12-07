
module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, execute, get } = deployments;
  const { deployer } = await getNamedAccounts();

  await deploy('UniqueIdentity', {
    from: deployer,
    proxy: {
      proxyContract: 'OpenZeppelinTransparentProxy',
      execute: {
        methodName: 'initialize',
        args: [deployer, ''],
      },
    },
    skipIfAlreadyDeployed: true,
    log: true,
  });

};

module.exports.dependencies = [];
module.exports.tags = ['mainnet', 'UniqueIdentity', 'next'];
