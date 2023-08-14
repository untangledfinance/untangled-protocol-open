const deployProxy = async (hre, contractName, initParams, initSignature) => {
  const { getNamedAccounts, deployments } = hre;
  const { deploy, execute, get, save } = deployments;
  const { deployer } = await getNamedAccounts();

  const contractImpl = await deploy(`${contractName}Impl`, {
    contract: contractName,
    skipIfAlreadyDeployed: true,
    from: deployer,
    args: [],
    log: true,
  });

  const contractProxy = await deploy(`${contractName}Proxy`, {
    contract: 'UpgradableProxy',
    skipIfAlreadyDeployed: true,
    from: deployer,
    args: [contractImpl.address],
    log: true,
  });

  if (contractProxy.newlyDeployed) {
    const contract = contractImpl;
    contract.address = contractProxy.address;
    await save(contractName, contract);
    await execute(contractName, { from: deployer, log: true }, initSignature || 'initialize', ...initParams);
  } else if (contractImpl.newlyDeployed) {
    await execute(`${contractName}Proxy`, { from: deployer, log: true }, 'updateImplementation', contractImpl.address);
    const contract = contractImpl;
    contract.address = contractProxy.address;
    await save(contractName, contract);
  }

  return contractProxy
};

module.exports = {
  deployProxy,
};
