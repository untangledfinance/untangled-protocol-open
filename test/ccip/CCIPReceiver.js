const { ethers, upgrades } = require('hardhat');
const { deployments } = require('hardhat');
const { expect } = require('../shared/expect.js');

const { parseEther } = ethers.utils;

describe('CCIPReceiver', () => {
  let untangedReceiver;
  // Wallets
  let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner;
  before('create fixture', async () => {
    [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner] =
      await ethers.getSigners();

    const UntangedReceiver = await ethers.getContractFactory('UntangedReceiver');
    untangedReceiver = await upgrades.deployProxy(UntangedReceiver, [untangledAdminSigner.address]);
  });

  describe('#Upgrade Proxy', async () => {
    it('Upgrade successfully', async () => {
      const UntangledReceiverV2 = await ethers.getContractFactory('UntangledReceiverV2');
      const untangledReceiverV2 = await upgrades.upgradeProxy(untangedReceiver.address, UntangledReceiverV2);

      expect(untangledReceiverV2.address).to.equal(untangedReceiver.address);

      const hello = await untangledReceiverV2.hello();
      expect(hello).to.equal('Hello world');
    });
  });
});
