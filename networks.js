// All supported networks and related contract addresses are defined here.
//
// LINK token addresses: https://docs.chain.link/resources/link-token-contracts/
// Price feeds addresses: https://docs.chain.link/data-feeds/price-feeds/addresses
// Chain IDs: https://chainlist.org/?testnets=true

require('dotenv').config();

const DEFAULT_VERIFICATION_BLOCK_CONFIRMATIONS = 2;

const npmCommand = process.env.npm_lifecycle_event;
const isTestEnvironment = npmCommand == 'test' || npmCommand == 'test:unit';

const PRIVATEKEY = process.env.PRIVATEKEY;

if (!isTestEnvironment && !PRIVATEKEY) {
  throw Error('Set the PRIVATEKEY environment variable with your EVM wallet private key');
}

const networks = {
  sepolia: {
    url: 'https://rpc-sepolia.rockx.com',
    gasPrice: undefined,
    accounts: PRIVATEKEY !== undefined ? [PRIVATEKEY] : [],
    // verifyApiKey: "THIS HAS NOT BEEN SET",
    chainId: 11155111,
    confirmations: DEFAULT_VERIFICATION_BLOCK_CONFIRMATIONS,
    nativeCurrencySymbol: 'ETH',

    // https://docs.chain.link/ccip/supported-networks/
    router: '0xd0daae2231e9cb96b94c8512223533293c3693bf',
    chainSelector: '16015286601757825753',
    linkToken: '0x779877A7B0D9E8603169DdbD7836e478b4624789',
    bnmToken: '0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05', // LINK/SEPOLIA-ETH
  },
  mumbai: {
    url: 'https://rpc.ankr.com/polygon_mumbai',
    gasPrice: undefined,
    // blockGasLimit: 100000000429720,
    accounts: PRIVATEKEY !== undefined ? [PRIVATEKEY] : [],
    // verifyApiKey: "THIS HAS NOT BEEN SET",
    chainId: 80001,
    confirmations: DEFAULT_VERIFICATION_BLOCK_CONFIRMATIONS,
    nativeCurrencySymbol: 'MATIC',

    // https://docs.chain.link/ccip/supported-networks/
    router: '0x70499c328e1E2a3c41108bd3730F6670a44595D1',
    chainSelector: '12532609583862916517',
    linkToken: '0x326C977E6efc84E512bB9C30f76E30c160eD06FB',
    bnmToken: '0xf1E3A5842EeEF51F2967b3F05D45DD4f4205FF40',
  },
};

module.exports = {
  networks,
};
