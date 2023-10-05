const { expect, assert } = require('chai');
const { ethers } = require('hardhat');
const { setup } = require('../setup');
const { time } = require('@nomicfoundation/hardhat-network-helpers');
const { BigNumber } = require('ethers');

const ONE_DAY_IN_SECONDS = 86400;

describe('MintedIncreasingInterestTGE', function() {
  let MintedIncreasingInterestTGE;
  let mintedIncreasingInterestTGE;
  let owner; // Replace with your contract owner's address
  let securitizationManager; // Replace with the address of the securitization manager or pool
  let accounts;
  let registry;
  let securitizationPool;
  let openingTime;
  let closingTime;
  let rate;
  let cap;

  let initialInterest ; // Your desired initial interest rate
  let finalInterest ; // Your desired final interest rate
  let timeInterval ; // 1 hour
  let amountChangeEachInterval ; // Your desired amount change

  before(async function() {
    MintedIncreasingInterestTGE = await ethers.getContractFactory('MintedIncreasingInterestTGE'); // Replace with your contract name
    [owner, securitizationManager, ...accounts] = await ethers.getSigners();
    ({ registry, noteTokenFactory } = await setup());

    const SecuritizationPool = await ethers.getContractFactory('SecuritizationPool');
    const NoteToken = await ethers.getContractFactory('NoteToken');

    mintedIncreasingInterestTGE = await MintedIncreasingInterestTGE.deploy(/* constructor arguments */); // Replace with constructor arguments if needed
    await mintedIncreasingInterestTGE.deployed();
    securitizationPool = await SecuritizationPool.deploy();
    const currencyAddress = await securitizationPool.underlyingCurrency();
    const longSale = true;
    const noteToken = await NoteToken.deploy('Test', 'TST', 18, securitizationPool.address, 1);

    await mintedIncreasingInterestTGE.initialize(registry.address, owner.address, noteToken.address, currencyAddress, longSale);

  });

  it('Get isLongSale', async () => {
    assert.equal(await mintedIncreasingInterestTGE.isLongSale(), true);
  });

  it('Set Yield', async () => {
    await mintedIncreasingInterestTGE.setYield(20);
    assert.equal(await mintedIncreasingInterestTGE.yield(), 20);
  });
  it('should allow the owner to set the interest rate range', async function () {
    initialInterest = 80000;
    finalInterest = 104000;
    timeInterval = 3600;
    amountChangeEachInterval = 1000;

    // Only the owner should be able to set the interest rate range
    await expect(
      mintedIncreasingInterestTGE
        .connect(accounts[0])
        .setInterestRange(initialInterest, finalInterest, timeInterval, amountChangeEachInterval)
    ).to.be.revertedWith('IncreasingInterestCrowdsale: Caller must be owner or pool');

    // The owner should be able to set the interest rate range
    await mintedIncreasingInterestTGE
      .connect(owner)
      .setInterestRange(initialInterest, finalInterest, timeInterval, amountChangeEachInterval);

    // Verify that the interest rate range was set correctly
    const actualInitialInterest = await mintedIncreasingInterestTGE.initialInterest();
    const actualFinalInterest = await mintedIncreasingInterestTGE.finalInterest();
    const actualTimeInterval = await mintedIncreasingInterestTGE.timeInterval();
    const actualAmountChangeEachInterval = await mintedIncreasingInterestTGE.amountChangeEachInterval();

    expect(actualInitialInterest).to.equal(BigNumber.from(initialInterest));
    expect(actualFinalInterest).to.equal(BigNumber.from(finalInterest));
    expect(actualTimeInterval).to.equal(BigNumber.from((timeInterval)));
    expect(actualAmountChangeEachInterval).to.equal(BigNumber.from(amountChangeEachInterval));
  });

  it('should allow the owner or pool to start a new round sale', async function() {
    openingTime = await time.latest() + 60; // Starts 1 minute from now
    closingTime = openingTime + ONE_DAY_IN_SECONDS; // Ends 1 hour after opening
    rate = 100; // Your desired rate
    cap = ethers.utils.parseEther('1000'); // Your desired cap in ether

    // Only the owner (or pool) should be able to start a new round sale
    await expect(
      mintedIncreasingInterestTGE
        .connect(accounts[0])
        .startNewRoundSale(openingTime, closingTime, rate, cap),
    ).to.be.revertedWith('MintedIncreasingInterestTGE: Caller must be owner or pool');

    // The owner (or pool) should be able to start a new round sale
    await mintedIncreasingInterestTGE
      .connect(owner)
      .startNewRoundSale(openingTime, closingTime, rate, cap);

    // Verify the new round sale parameters
    const _openTime = await mintedIncreasingInterestTGE.openingTime(); // Replace with the correct function for fetching round info
    const _closingTime = await mintedIncreasingInterestTGE.closingTime(); // Replace with the correct function for fetching round info
    const _rate = await mintedIncreasingInterestTGE.rate(); // Replace with the correct function for fetching round info
    const _cap = await mintedIncreasingInterestTGE.totalCap(); // Replace with the correct function for fetching round info
    expect(_openTime.toNumber()).to.equal(openingTime);
    expect(_closingTime.toNumber()).to.equal(closingTime);
    expect(_rate.toNumber()).to.equal(rate);
    expect(_cap).to.equal(cap);
  });
  it('should set correct picked interest when finalize', async () => {
    await expect(
      mintedIncreasingInterestTGE.finalize(false,  await securitizationPool.pot())
    ).to.be.revertedWith('FinalizableCrowdsale: not closed')
    await time.increaseTo(closingTime + ONE_DAY_IN_SECONDS);
    await mintedIncreasingInterestTGE.finalize(false, await securitizationPool.pot());
    const pickedInterest = await mintedIncreasingInterestTGE.pickedInterest();
    expect(pickedInterest).to.equal(BigNumber.from(finalInterest));

  });
});
