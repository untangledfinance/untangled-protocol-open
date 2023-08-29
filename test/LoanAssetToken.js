const { ethers } = require('hardhat');
const { deployments } = require('hardhat');
const { expect } = require('./shared/expect.js');

const ONE_DAY = 86400;
describe('LoanAssetToken', () => {
  let loanAssetTokenContract;

  // Wallets
  let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner;
  before('create fixture', async () => {
    [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner] = await ethers.getSigners();
    loanAssetTokenContract = await ethers.getContractAt(
      'LoanAssetToken',
      (await get('LoanAssetToken')).address,
    );

  });

  describe('#mint', async () => {
    it('only LoanKernel contract can mint', async function() {
    });

  });

  describe('#burn', async () => {
    it('only LoanKernel contract can burn', async function() {
    });

  });
});
