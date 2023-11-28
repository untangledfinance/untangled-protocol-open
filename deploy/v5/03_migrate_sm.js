const { getChainId } = require('hardhat');

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, read, get } = deployments;
    const { deployer } = await getNamedAccounts();

    await deployments.deploy('SecuritizationManager', {
        from: deployer,
        proxy: {
            proxyContract: 'OpenZeppelinTransparentProxy',
        },
        log: true,
    });
};

module.exports.dependencies = ['registry'];
module.exports.tags = ['v5', 'mainnet', 'SecuritizationManager'];
