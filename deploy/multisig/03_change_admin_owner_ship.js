const { getChainId } = require('hardhat');

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { readDotFile, deploy, execute, get, save } = deployments;
  const { deployer } = await getNamedAccounts();

  const untangledBridgeRouter = await deployments.get('UntangledBridgeRouter');
  const proxyAdminDeployment = await deployments.get('DefaultProxyAdmin');
  const proxyAdmin = await ethers.getContractAt(
    '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol:ProxyAdmin',
    proxyAdminDeployment.address
  );

  const bridgeRouterAdmin = await proxyAdmin.getProxyAdmin(untangledBridgeRouter.address);

  console.log(bridgeRouterAdmin);

  await deployments.execute(
    'DefaultProxyAdmin',
    {
      from: deployer,
    },
    'changeProxyAdmin',
    untangledBridgeRouter.address,
    '0x7a35210B5151147f25B2984686222f3BF68a0fdc'
  );
};

module.exports.dependencies = [];
module.exports.tags = ['change_admin_multisig'];
