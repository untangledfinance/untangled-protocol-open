const { ethers, upgrades } = require("hardhat");

const UPGRADEABLE_PROXY = "0x69E5648960EB6B55c72adc035D2632d562869C17";

async function main() {
   const gas = await ethers.provider.getGasPrice()
   const V2Contract = await ethers.getContractFactory("DistributionAssessor");
   console.log("Upgrading V1Contract...");
   let upgrade = await upgrades.upgradeProxy(UPGRADEABLE_PROXY, V2Contract, {
      gasPrice: gas
   });
   console.log("V1 Upgraded to V2");
   console.log("V2 Contract Deployed To:", upgrade.address)
}

main().catch((error) => {
   console.error(error);
   process.exitCode = 1;
 });