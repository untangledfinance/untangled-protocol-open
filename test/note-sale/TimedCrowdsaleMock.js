const { artifacts, ethers } = require('hardhat');
const { setup, initPool } = require('../setup');
const { expect, assert } = require('chai');
const { BigNumber, providers, utils } = require('ethers');
const { keccak256 } = require('@ethersproject/keccak256');
const { getPoolByAddress } = require('../utils');
const { POOL_ADMIN_ROLE } = require('../constants');

const ONE_DAY = 86400;
const DECIMAL = BigNumber.from(10).pow(18);
describe('TimedCrowdsaleMock', () => {
  let registry;
  let securitizationPool;
  let timedCrowdsale;
  let stableCoin;
  let poolCreatorSigner;

  before('create fixture', async () => {
    ({ registry, noteTokenFactory, stableCoin, securitizationManager } = await setup());
    const SecuritizationPool = await ethers.getContractFactory('SecuritizationPool');
    const NoteToken = await ethers.getContractFactory('NoteToken');

    const [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer] =
      await ethers.getSigners();


    const OWNER_ROLE = await securitizationManager.OWNER_ROLE();
    await securitizationManager.setRoleAdmin(POOL_ADMIN_ROLE, OWNER_ROLE);
    await securitizationManager.grantRole(OWNER_ROLE, borrowerSigner.address);
    await securitizationManager.connect(borrowerSigner).grantRole(POOL_ADMIN_ROLE, poolCreatorSigner.address);

    // securitizationPool = await SecuritizationPool.deploy();
    // await initPool(securitizationPool);

    const salt = utils.keccak256(Date.now());

    // Create new pool
    let transaction = await securitizationManager
      .connect(poolCreatorSigner)

      .newPoolInstance(
        salt,

        poolCreatorSigner.address,
        utils.defaultAbiCoder.encode([
          {
            type: 'tuple',
            components: [
              {
                name: 'currency',
                type: 'address'
              },
              {
                name: 'minFirstLossCushion',
                type: 'uint32'
              },
              {
                name: 'validatorRequired',
                type: 'bool'
              }
            ]
          }
        ], [
          {
            currency: stableCoin.address,
            minFirstLossCushion: '100000',
            validatorRequired: true
          }
        ]));


    let receipt = await transaction.wait();
    let [securitizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;

    const securitizationPool = await getPoolByAddress(securitizationPoolAddress);


    const noteToken = await upgrades.deployProxy(NoteToken, ['Test', 'TST', 18, securitizationPool.address, 1], {
      initializer: 'initialize(string,string,uint8,address,uint8)',
    });
    const currencyAddress = await securitizationPool.underlyingCurrency();

    const TimedCrowdsaleMock = await ethers.getContractFactory('TimedCrowdsaleMock');
    timedCrowdsale = await TimedCrowdsaleMock.deploy();

    timedCrowdsale.initialize(registry.address, securitizationPool.address, noteToken.address, currencyAddress);
  });

  it('#newSaleRoundTime', async () => {
    expect(await timedCrowdsale.hasClosed()).to.be.true;

    const [, , anotherGuy] = await ethers.getSigners();
    await expect(timedCrowdsale.connect(anotherGuy).newSaleRoundTime(0, 10)).to.be.revertedWith(
      'Crowdsale: Caller must be owner or pool'
    );
    await expect(timedCrowdsale.newSaleRoundTime(10, 0)).to.be.revertedWith(
      'TimedCrowdsale: opening time is not before closing time'
    );

    const currentBlockTime = (await providers.getDefaultProvider().getBlock()).timestamp;
    const tx = await timedCrowdsale.newSaleRoundTime(currentBlockTime + 100, currentBlockTime + 1000);
    expect(tx).to.be.emit(timedCrowdsale, 'UpdateSaleRoundTime');
  });

  it('checkOnlyWhiteOpen', async () => {
    await expect(timedCrowdsale.checkOnlyWhileOpen()).to.be.revertedWith('TimedCrowdsale: not open');
  });

  it('#setUsingTimeLimit', async () => {
    expect(await timedCrowdsale.isOpen()).to.be.false; // time to low (0,10)

    const tx = await timedCrowdsale.setUsingTimeLimit(false);
    expect(tx).to.be.emit(timedCrowdsale, 'UpdateUsingTimeLimit').withArgs(false);
    expect(await timedCrowdsale.isOpen()).to.be.true;
    expect(await timedCrowdsale.isEnableTimeLimit()).to.be.false;
  });

  it('#extendTime', async () => {
    await expect(timedCrowdsale.extendTime(1000)).to.be.revertedWith(
      'TimedCrowdsale: new closing time is before current closing time'
    );
    const oldClosingTime = await timedCrowdsale.closingTime();
    const newClosingTime = oldClosingTime.add(2);
    const tx = await timedCrowdsale.extendTime(newClosingTime);
    expect(tx).to.be.emit(timedCrowdsale, 'TimedCrowdsaleExtended');
    expect(await timedCrowdsale.closingTime()).to.be.eq(newClosingTime);
  });

  it('#addFunding', async () => {
    const totalCap = await timedCrowdsale.totalCap();
    await timedCrowdsale.addFunding(1000);

    const newTotalCap = await timedCrowdsale.totalCap();
    expect(1000).to.be.eq(newTotalCap.sub(totalCap));
  });

  it('#getCurrencyRemainAmount', async () => {
    // no raise ...
    await timedCrowdsale.addFunding(1000);
    expect(await timedCrowdsale.getCurrencyRemainAmount()).to.be.eq(2000);
  });

  it('#getTokenRemainAmount', async () => {
    const totalToken = await timedCrowdsale.getTokenRemainAmount();
    expect(totalToken).to.be.eq(0);
  });

  it('#totalCapReached', async () => {
    const totalCapReached = await timedCrowdsale.totalCapReached();
    expect(totalCapReached).to.be.false;
  });

  it('#getTokenAmount', async () => {
    // default is 0
    expect(await timedCrowdsale.getTokenAmount(1000)).to.be.eq(0);
  });

  it('#hasClose', async () => {
    expect(await timedCrowdsale.hasClosed()).to.be.false;
  });
});
