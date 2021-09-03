/**
 * @type import('hardhat/config').HardhatUserConfig
 */
require('hardhat-deploy');
require('@nomiclabs/hardhat-ethers');
const dotenv = require('dotenv');

dotenv.config();
const DEPLOYER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;

module.exports = {
  defaultNetwork: "testnet",
  solidity: "0.5.0",
  networks: {
    testnet: {
      chainId: 3603102,
      url: "https://rpc.testnet.dex.io",
      accounts: [`0x${DEPLOYER_PRIVATE_KEY}`]
    }
  },
  namedAccounts: {
    deployer: {
      default: 0,
    }
  }
};
