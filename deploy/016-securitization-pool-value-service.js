
module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, execute, get } = deployments;
    const { deployer } = await getNamedAccounts();

    const securitizationPoolValueService = await deploy('SecuritizationPoolValueService', {
        from: deployer,
        proxy: {
            proxyContract: 'OpenZeppelinTransparentProxy',
        },
        log: true,
    });

    await execute('Registry', { from: deployer, log: true }, 'setSecuritizationPoolValueService', securitizationPoolValueService.address);
};

module.exports.dependencies = ['Registry'];
module.exports.tags = ['next', 'mainnet', 'SecuritizationPoolValueService'];
