import { ethers, upgrades } from "hardhat";

async function main() {
  // Deploying
  const SP = await ethers.getContractFactory("SP_Bet");
  const SBT = await ethers.getContractFactory("SuperBetaToken");
  const instance = await upgrades.deployProxy(SP);
  await instance.deployed();
}

main();
