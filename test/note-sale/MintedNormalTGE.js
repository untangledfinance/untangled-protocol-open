const { artifacts } = require('hardhat');
const { setup } = require('../setup');
const { expect, assert } = require('chai');
const { BigNumber } = require('ethers');

const ONE_DAY = 86400;
const DECIMAL = BigNumber.from(10).pow(18);
describe('MintedNormalTGE', () => {
  let mintedNormalTGE;
  let registry;
  let securitizationPool;

  before('create fixture', async () => {
    const [poolTest] = await ethers.getSigners();
    ({ registry, noteTokenFactory } = await setup());
    const SecuritizationPool = await ethers.getContractFactory('SecuritizationPool');
    const MintedNormalTGE = await ethers.getContractFactory('MintedNormalTGE');
    const NoteToken = await ethers.getContractFactory('NoteToken');

    mintedNormalTGE = await MintedNormalTGE.deploy();
    securitizationPool = await SecuritizationPool.deploy();
    const currencyAddress = await securitizationPool.underlyingCurrency();
    const longSale = true;
    const noteToken = await NoteToken.deploy('Test', 'TST', 18, securitizationPool.address, 1);

    await mintedNormalTGE.initialize(registry.address, poolTest.address, noteToken.address, currencyAddress, longSale);
  });

  it('Get isLongSale', async () => {
    assert.equal(await mintedNormalTGE.isLongSale(), true);
  });

  it('Set Yield', async () => {
    await mintedNormalTGE.setYield(20);
    assert.equal(await mintedNormalTGE.yield(), 20);
  });

  it('Setup LongSale', async () => {
    await mintedNormalTGE.setupLongSale(20, 86400, Math.trunc(Date.now() / 1000));
  });

  it('Setup newRoundSale', async () => {
    const openingTime = Math.floor(Date.now() / 1000) + 60; // Starts 1 minute from now
    const closingTime = openingTime + 3600; // Ends 1 hour after opening
    const rate = 100; // Your desired rate
    const cap = ethers.utils.parseEther('1000'); // Your desired cap in ether
    const [owner, securitizationManager, ...accounts] = await ethers.getSigners();

    // Only the owner (or pool) should be able to start a new round sale
    await expect(
      mintedNormalTGE
        .connect(accounts[0])
        .startNewRoundSale(openingTime, closingTime, rate, cap)
    ).to.be.revertedWith('MintedNormalTGE: Caller must be owner or pool');

    // The owner (or pool) should be able to start a new round sale
    await mintedNormalTGE
      .connect(owner)
      .startNewRoundSale(openingTime, closingTime, rate, cap);

    // Verify the new round sale parameters
    const _openTime = await mintedNormalTGE.openingTime(); // Replace with the correct function for fetching round info
    const _closingTime = await mintedNormalTGE.closingTime(); // Replace with the correct function for fetching round info
    const _rate = await mintedNormalTGE.rate(); // Replace with the correct function for fetching round info
    const _cap = await mintedNormalTGE.totalCap(); // Replace with the correct function for fetching round info
    expect(_openTime.toNumber()).to.equal(openingTime);
    expect(_closingTime.toNumber()).to.equal(closingTime);
    expect(_rate.toNumber()).to.equal(rate);
    expect(_cap).to.equal(cap);
  });

  it('Setup initialAmount', async () => {
    const expectedInitialAmount = 1000; // Replace with your desired initial amount

    await mintedNormalTGE.setInitialAmount(expectedInitialAmount);

    const actualInitialAmount = await mintedNormalTGE.initialAmount();
    expect(actualInitialAmount).to.equal(expectedInitialAmount);
  });
});
