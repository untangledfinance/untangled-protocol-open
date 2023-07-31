const { ethers, upgrades } = require("hardhat");

async function main() {
   const gas = await ethers.provider.getGasPrice()
   const V1contract = await ethers.getContractFactory("Registry");
   console.log("Deploying V1contract...");
   const v1contract = await upgrades.deployProxy(V1contract );
   await v1contract.deployed();
   console.log(9, v1contract)
   console.log("V1 Contract deployed to:", v1contract.address);
}

main().catch((error) => {
   console.error(error);
   process.exitCode = 1;
 });
