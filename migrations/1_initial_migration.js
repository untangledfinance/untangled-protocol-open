// const NoteToken = artifacts.require("NoteToken");
const Registry = artifacts.require("Registry");
module.exports = async function (deployer, accounts) {
  console.log(4, accounts[1])
  deployer.deploy(Registry);
  const RegistryContract = await Registry.deployed();
  console.log(6, RegistryContract.address)
};
