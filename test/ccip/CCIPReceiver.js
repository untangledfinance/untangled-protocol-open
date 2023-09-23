const { ethers, upgrades } = require('hardhat');
const { deployments } = require('hardhat');
const { expect } = require('.chai');

const { parseEther, defaultAbiCoder } = ethers.utils;

const abiCoder = new ethers.utils.AbiCoder();

describe('CCIPReceiver', () => {
  let untangledReceiver;
  let untangledBridgeRouter;

  let userData;

  // Wallets
  let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner;
  before('create fixture', async () => {
    [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner] =
      await ethers.getSigners();

    const UntangledBridgeRouter = await ethers.getContractFactory('UntangledBridgeRouter');
    untangledBridgeRouter = await upgrades.deployProxy(UntangledBridgeRouter, [untangledAdminSigner.address]);

    const UntangledReceiver = await ethers.getContractFactory('UntangledReceiver');
    untangledReceiver = await upgrades.deployProxy(UntangledReceiver, [
      untangledAdminSigner.address,
      untangledBridgeRouter.address,
    ]);

    const CCIP_RECEIVER_ROLE = await untangledBridgeRouter.CCIP_RECEIVER_ROLE();
    await untangledBridgeRouter.grantRole(CCIP_RECEIVER_ROLE, untangledReceiver.address);
  });

  describe('#Receiver', async () => {
    it('should receive message successfully', async () => {
      userData = abiCoder.encode(['address', 'uint256'], [lenderSigner.address, parseEther('100')]);
      const sender = abiCoder.encode(['address'], [lenderSigner.address]);

      const data = defaultAbiCoder.encode(['uint8', 'bytes'], [0, userData]);

      await untangledReceiver.connect(untangledAdminSigner).ccipReceive({
        messageId: ethers.constants.HashZero,
        sourceChainSelector: 1234,
        sender: sender,
        data: data,
        destTokenAmounts: [],
      });

      const result = await untangledReceiver.getLastReceivedMessageDetails();

      expect(result.messageId).to.equal(ethers.constants.HashZero);
      expect(result.command.messageType).to.equal(0);
      expect(result.command.data).to.equal(userData);

      const messageDataGroup = await untangledReceiver.messageDataGroup(ethers.constants.HashZero);

      expect(messageDataGroup.messageType).to.equal(0);
      expect(messageDataGroup.data).to.equal(userData);

      const failedMessageDataGroup = await untangledReceiver.failedMessageDataGroup(ethers.constants.HashZero);
      console.log('failedMessageDataGroup', failedMessageDataGroup);
    });
  });

  describe('#Upgrade Proxy', async () => {
    it('Upgrade successfully', async () => {
      const UntangledReceiverV2 = await ethers.getContractFactory('UntangledReceiverV2');
      const untangledReceiverV2 = await upgrades.upgradeProxy(untangledReceiver.address, UntangledReceiverV2);

      expect(untangledReceiverV2.address).to.equal(untangledReceiver.address);

      const hello = await untangledReceiverV2.hello();
      expect(hello).to.equal('Hello world');

      const result = await untangledReceiverV2.getLastReceivedMessageDetails();

      expect(result.messageId).to.equal(ethers.constants.HashZero);
      expect(result.command.messageType).to.equal(0);
      expect(result.command.data).to.equal(userData);

      const messageDataGroup = await untangledReceiverV2.messageDataGroup(ethers.constants.HashZero);

      expect(messageDataGroup.messageType).to.equal(0);
      expect(messageDataGroup.data).to.equal(userData);
    });
  });
});
