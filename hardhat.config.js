require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");
require("hardhat-gas-reporter");
require('dotenv').config();
require('hardhat-deploy');

module.exports = {
  solidity: {
    version: "0.8.7",
    ...(process.env.DEPLOY === "true" &&
    {
      settings: {
        optimizer: {
          enabled: true,
          runs: 999999,
        },
      },
    }
    )
  },
  namedAccounts: {
    deployer: 0,
  },
  networks: {
    hardhat: {
      forking: {
        url: process.env.GOERLI_RPC
      }
    },
    mainnet: {
      url: process.env.ETH_RPC,
      accounts: [process.env.PRIVATEKEY],
      gasMultiplier: 1.5,
    },
    kovan: {
      url: process.env.KOVAN_RPC,
      accounts: [process.env.PRIVATEKEY],
      gasMultiplier: 1.5,
    },
    goerli: {
      url: process.env.GOERLI_RPC,
      accounts: [process.env.PRIVATEKEY],
      gasMultiplier: 1.5,
    },
    fuji: {
      url: 'https://rpc.ankr.com/avalanche_fuji',
      accounts: [process.env.PRIVATEKEY],
      gasMultiplier: 1.5,
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN
  },
};