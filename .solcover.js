module.exports = {
  configureYulOptimizer: true,
  skipFiles: [
    'test/TestERC20.sol', 
    'test/TestUniqueIdentity.sol',
    'protocol/note-sale/crowdsale/TimedCrowdsaleMock.sol'
  ],
};
