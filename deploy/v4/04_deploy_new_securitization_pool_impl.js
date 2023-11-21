const { registrySet } = require('../v2/utils');

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { readDotFile, deploy, execute, get, save } = deployments;
    const { deployer } = await getNamedAccounts();

    await deployments.deploy('SecuritizationPool', {
        from: deployer,
        args: [],
        log: true,
    });

    const contracts = ['SecuritizationPool'];

    await registrySet(contracts);
};

module.exports.dependencies = [];
module.exports.tags = ['v4', 'mainnet', 'securitization_pool_new_deployment'];
