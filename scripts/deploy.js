const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying BidKernel contracts with account:", deployer.address);

  // Use the deployer as the default arbiter for local testing.
  // For production deployments replace this with a dedicated multi-sig or DAO address.
  const arbiterAddress = deployer.address;

  const Marketplace = await hre.ethers.getContractFactory("Marketplace");
  const marketplace = await Marketplace.deploy(arbiterAddress);
  await marketplace.waitForDeployment();

  console.log("Marketplace deployed to:", await marketplace.getAddress());
  console.log("Arbiter:                ", arbiterAddress);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
