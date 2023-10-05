module.exports = {
  configureYulOptimizer: true,
  skipFiles: [
    'test/TestERC20.sol',
    'test/TestUniqueIdentity.sol',
    'protocol/note-sale/crowdsale/mock',
    'protocol/ccip',
    'external',
    'base/UpgradableProxy.sol',
    'protocol/pool/mock',
  ],
};
