const { artifacts } = require('hardhat');
const { setup } = require('../setup');
const { expect } = require('chai');
const { BigNumber } = require('ethers');
const { keccak256 } = require('@ethersproject/keccak256');

describe('TokenGenerationEventFactory', () => {
  let registry;
  let tokenGenerationEventFactory;
  let securitizationManager;
  let stableCoin;
  let poolCreatorSigner;

  before('create fixture', async () => {
    ({ registry, tokenGenerationEventFactory, stableCoin, securitizationManager, uniqueIdentity } = await setup());

    [, , poolCreatorSigner] = await ethers.getSigners();

    const POOL_CREATOR_ROLE = keccak256(Buffer.from('POOL_CREATOR'));
    await securitizationManager.grantRole(POOL_CREATOR_ROLE, poolCreatorSigner.address);
  });

  it('#pauseUnpauseTge', async () => {
    const poolTx = await securitizationManager.connect(poolCreatorSigner).newPoolInstance(stableCoin.address, 0);
    const poolTxWait = await poolTx.wait();
    const poolAddress = poolTxWait.events.find((x) => x.event == 'NewPoolCreated').args.instanceAddress;

    const [issuer] = await ethers.getSigners();
    // const securitizationPool = await SecuritizationPool.deploy();
    // const noteToken = await NoteToken.deploy('Test', 'TST', 18, securitizationPool.address, 1);
    // const currencyAddress = await securitizationPool.underlyingCurrency();

    const tx = await securitizationManager
      .connect(poolCreatorSigner)
      .initialTGEForSOT(issuer.address, poolAddress, [0, 2], true, 'SENIOR');
    const txWait = await tx.wait();

    const tgeAddress = txWait.events.find((x) => x.event == 'NewTGECreated').args.instanceAddress;

    await expect(tokenGenerationEventFactory.pauseUnpauseTge(tgeAddress)).to.not.be.reverted;
  });

  it('#unPauseAllTges', async () => {
    await expect(tokenGenerationEventFactory.pauseUnpauseAllTges()).to.not.be.reverted;
  });
});
