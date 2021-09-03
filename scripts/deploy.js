// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");
const ethers = hre.ethers;

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // We get the contract to deploy
  const DexchangeCore = await ethers.getContractFactory("DexchangeCore");
  const dexchangeCore = await DexchangeCore.deploy();

  await dexchangeCore.deployed();

  console.log("DexchangeCore deployed to:", dexchangeCore.address);


  const DexIDOPool = await ethers.getContractFactory("DexIDOPool");
  const dexIDOPool = await DexIDOPool.deploy();

  await dexIDOPool.deployed();

  console.log("DexIDOPool deployed to:", dexIDOPool.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });