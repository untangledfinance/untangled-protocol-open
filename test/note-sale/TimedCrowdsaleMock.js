const { artifacts } = require('hardhat');
const { setup } = require('../setup');
const { expect, assert } = require('chai');
const { BigNumber, providers } = require('ethers');

const SecuritizationPool = artifacts.require('SecuritizationPool');
const NoteToken = artifacts.require('NoteToken');

const ONE_DAY = 86400;
const DECIMAL = BigNumber.from(10).pow(18);
describe('TimedCrowdsaleMock', () => {
  let registry;
  let securitizationPool;
  let timedCrowdsale;

  before('create fixture', async () => {
    ({ registry, noteTokenFactory } = await setup());

    securitizationPool = await SecuritizationPool.new();
    const noteToken = await NoteToken.new('Test', 'TST', 18, securitizationPool.address, 1);
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

  it('#hasClose', async () => {
    expect(await timedCrowdsale.hasClosed()).to.be.false;
  });
});
