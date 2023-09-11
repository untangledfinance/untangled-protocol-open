require('solidity-coverage');
require('@nomiclabs/hardhat-truffle5');
require('@nomiclabs/hardhat-web3');
require('@nomiclabs/hardhat-etherscan');
require('hardhat-contract-sizer');
require('hardhat-deploy');
require('@openzeppelin/hardhat-upgrades');
require('@nomiclabs/hardhat-waffle');

require('dotenv').config();
const MNEMONIC = process.env.MNEMONIC;

const accounts = {
  mnemonic: MNEMONIC ?? 'choice lizard word used slam master witness ill connect cloth nice destroy',
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
    invoiceOperator: '0x5380e40aFAd8Cdec0B841c4740985F1735Aa5aCB',
  },
  networks: {
    hardhat: {
      blockGasLimit: 12500000,
      saveDeployments: true,
      allowUnlimitedContractSize: false,
      accounts,
      
      forking: {
        url: 'https://polygon-mumbai.g.alchemy.com/v2/BGyZWFgdfbIagWLGrf8rSxo1EQr2a7f4',
        blockNumber: 39993365
      }
    },
    celo: {
      saveDeployments: true,
      accounts,
      loggingEnabled: true,
      url: `https://forno.celo.org`,
    },
    alfajores: {
      saveDeployments: true,
      accounts: accounts,
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
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: 'QHKKRV5QTID4QH9MMIKU6ADXNIIHE1V4Z4',
    customChains: [
      {
        network: 'alfajores',
        chainId: 44787,
        urls: {
          apiURL: 'https://api-alfajores.celoscan.io/api',
          browserURL: 'https://api-alfajores.celoscan.io',
        },
      },
    ],
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
