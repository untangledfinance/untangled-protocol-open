module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, execute, get } = deployments;
    const { deployer } = await getNamedAccounts();

    const registry = await get('Registry');
    const proxyAdmin = await get('DefaultProxyAdmin');

    const PoolNAVFactory = await get('PoolNAVFactory');

    const poolNav = await deploy('PoolNAV', {
        from: deployer,
        log: true,
    });

    await execute('PoolNAVFactory', { from: deployer, log: true }, 'setPoolNAVImplementation', poolNav.address);
};

module.exports.dependencies = ['Registry'];
module.exports.tags = ['next', 'mainnet', 'PoolNAV'];
