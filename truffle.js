require('dotenv').config();
const TestRPC = require('ganache');
const HDWalletProvider = require('@truffle/hdwallet-provider');

module.exports = {
  compilers: {
    solc: {
      version: '0.8.13',
      settings: {
        optimizer: {
          enabled: true,
          runs: 1,
        },
      },
    },
  },
  networks: {
    development: {
      provider: TestRPC.provider(),
      port: process.env.RPC_PORT,
      network_id: '*', // Match any network id
    },
    alfajores: {
      provider: () => {
        if (process.env.MNEMONIC) {
          return new HDWalletProvider(process.env.MNEMONIC, process.env.BINKABI_INFURA_URI_ALFAJORES);
        }
        return TestRPC.provider();
      },
      from: process.env.WALLET_ADDRESS,
      gas: 8812388,
      gasPrice: 8000000000,
      network_id: 44787,
    },
  },
  migrations_directory: process.env.MIGRATION_DIRRECTORY,
};
