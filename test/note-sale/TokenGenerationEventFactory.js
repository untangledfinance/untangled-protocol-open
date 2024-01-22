const { artifacts } = require('hardhat');
const { setup } = require('../setup');
const { expect } = require('chai');
const { BigNumber, utils } = require('ethers');
const { keccak256 } = require('@ethersproject/keccak256');
const { parseEther } = ethers.utils;

const { POOL_ADMIN_ROLE } = require('../constants.js');
const UntangledProtocol = require('../shared/untangled-protocol');

describe('TokenGenerationEventFactory', () => {
  let registry;
  let tokenGenerationEventFactory;
  let securitizationManager;
  let stableCoin;
  let poolCreatorSigner;
  let untangledProtocol;

  before('create fixture', async () => {
    const contracts = await setup();
    untangledProtocol = UntangledProtocol.bind(contracts);
    ({ registry, tokenGenerationEventFactory, stableCoin, securitizationManager } = await setup());

    [, , poolCreatorSigner] = await ethers.getSigners();

    await securitizationManager.grantRole(POOL_ADMIN_ROLE, poolCreatorSigner.address);
  });

  it('#pauseUnpauseTge', async () => {
    const poolAddress = await untangledProtocol.createSecuritizationPool(poolCreatorSigner);

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
