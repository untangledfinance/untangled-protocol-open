const hre = require("hardhat");
async function main() {


  const SecuritizationPoolValueService = await hre.ethers.getContractFactory("SecuritizationPoolValueService");
  const securitizationPoolValueService = await SecuritizationPoolValueService.deploy();
  await securitizationPoolValueService.deployed();
  console.log("SecuritizationPoolValueService deployed to:", securitizationPoolValueService.address);





}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});