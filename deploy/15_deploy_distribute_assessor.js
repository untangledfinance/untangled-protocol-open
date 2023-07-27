const hre = require("hardhat");
async function main() {


  const DistributionAssessor = await hre.ethers.getContractFactory("DistributionAssessor");
  const distributionAssessor = await DistributionAssessor.deploy();
  await distributionAssessor.deployed();
  console.log("DistributionAssessor deployed to:", distributionAssessor.address);





}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});