require('@nomiclabs/hardhat-truffle5');
require('@nomiclabs/hardhat-web3');
require('@nomiclabs/hardhat-etherscan');
require('hardhat-contract-sizer');
require('hardhat-deploy');
require('@openzeppelin/hardhat-upgrades');
require("@nomiclabs/hardhat-waffle");

require('dotenv').config();
const MNEMONIC = process.env.MNEMONIC;

const accounts = {
  mnemonic: MNEMONIC ?? 'test test test test test test test test test test test junk',
};

module.exports = {
  solidity: {
    compilers: [
      {
        version: '0.8.13',
        settings: {
          optimizer: {
            enabled: true,
            runs: 999999,
          },
        },
      },
    ],
    overrides: {
      'contracts/protocol/pool/SecuritizationPool.sol': {
        version: '0.8.13',
        settings: {
          optimizer: {
            enabled: true,
            runs: 9999,
          },
        },
      },
    },
  },
  defaultNetwork: 'hardhat',
  namedAccounts: {
    deployer: 0,
    invoiceOperator: '0x5380e40aFAd8Cdec0B841c4740985F1735Aa5aCB'
  },
  networks: {
    hardhat: {
      blockGasLimit: 12500000,
      saveDeployments: true,
      allowUnlimitedContractSize: false,
      accounts,
    },
    celo: {
      saveDeployments: true,
      accounts,
      loggingEnabled: true,
      url: `https://forno.celo.org`,
    },
    alfajores: {
      saveDeployments: true,
      accounts,
      loggingEnabled: true,
      url: `https://alfajores-forno.celo-testnet.org`,
    },
    rinkeby: {
      saveDeployments: true,
      accounts,
      loggingEnabled: true,
      url: `https://rinkeby.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161`,
    },
  },
  mocha: {
    timeout: 200000,
  },
  paths: {
    sources: './contracts',
    tests: './test',
    artifacts: './artifacts',
    cache: './cache',
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: false,
  },
};
