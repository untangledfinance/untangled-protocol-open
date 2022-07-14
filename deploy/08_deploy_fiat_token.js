module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, get } = deployments;
  const { deployer } = await getNamedAccounts();
  const TokenTopupController = await get('TokenTopupController');

  await deploy(`FiatToken`, {
    contract: 'FiatToken',
    skipIfAlreadyDeployed: true,
    from: deployer,
    args: [TokenTopupController.address, "NGN Token", "NGN", 2],
    log: true,
  });
};

module.exports.dependencies = ['top_up'];
module.exports.tags = ['fiat_token'];
