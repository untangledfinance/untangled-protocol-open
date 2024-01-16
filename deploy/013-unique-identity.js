const { networks } = require('../networks');

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, execute, get, read } = deployments;
    const { deployer } = await getNamedAccounts();

    await deploy('UniqueIdentity', {
        from: deployer,
        proxy: {
            proxyContract: 'OpenZeppelinTransparentProxy',
            execute: {
                init: {
                    methodName: 'initialize',
                    args: [deployer, ''],
                },
            },
        },
        // skipIfAlreadyDeployed: true,
        log: true,
    });

    const kycAdmin = network.config.kycAdmin;

    const SIGNER_ROLE = await read('UniqueIdentity', 'SIGNER_ROLE');
    await execute(
        'UniqueIdentity',
        {
            from: deployer,
            log: true,
        },
        'grantRole',
        SIGNER_ROLE,
        kycAdmin
    );

    const SUPER_ADMIN = await read('UniqueIdentity', 'SUPER_ADMIN');
    await execute(
        'UniqueIdentity',
        {
            from: deployer,
            log: true,
        },
        'addSuperAdmin',
        SUPER_ADMIN,
        kycAdmin
    );
};

module.exports.dependencies = [];
module.exports.tags = ['mainnet', 'UniqueIdentity', 'next'];
