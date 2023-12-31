// module.exports = async ({ getNamedAccounts, deployments }) => {
//     const { deploy, execute, get } = deployments;
//     const { deployer } = await getNamedAccounts();

//     const registry = await get('Registry');
//     const proxyAdmin = await get('DefaultProxyAdmin');

//     const PoolNAVFactory = await deploy('PoolNAVFactory', {
//         from: deployer,
//         proxy: {
//             proxyContract: 'OpenZeppelinTransparentProxy',

//             execute: {
//                 init: {
//                     methodName: 'initialize',
//                     args: [registry.address, proxyAdmin.address],
//                 },
//             },
//         },
//         log: true,
//     });

//     await execute('Registry', { from: deployer, log: true }, 'setPoolNAVFactory', PoolNAVFactory.address);
// };

// module.exports.dependencies = ['Registry'];
// module.exports.tags = ['next', 'mainnet', 'PoolNAVFactory'];

// We dont need this anymore
