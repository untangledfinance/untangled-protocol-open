const hre = require("hardhat");
async function main() {
 
  const Contract = await hre.ethers.getContractFactory("NoteTokenFactory");
  const instance = await Contract.deploy();
  await instance.deployed();
  // console.log(8, Contract)
  console.log("Contract deployed to:", instance.address);

}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});