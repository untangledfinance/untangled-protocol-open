const { ethers } = require('hardhat');
const { deployments } = require('hardhat');
const { BigNumber } = require('ethers');
const dayjs = require('dayjs');
const { parseEther, formatEther } = ethers.utils;

const { expect } = require('./shared/expect.js');
const { setup } = require('./setup.js');
const { unlimitedAllowance } = require('./utils.js');
const RATE_SCALING_FACTOR = 10 ** 4;

const SaleType = {
  MINTED_INCREASING_INTEREST: 0,
  NORMAL_SALE: 1,
};

describe('SecuritizationManager', () => {
  let stableCoin;
  let securitizationManager;
  let securitizationPoolContract;

  // Wallets
  let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner;
  before('create fixture', async () => {
    [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner] =
      await ethers.getSigners();

    ({ stableCoin, securitizationManager } = await setup());

    await stableCoin.transfer(lenderSigner.address, parseEther('1000'));
  });

  it('should emit RoleGranted event with an address', async function () {
    const POOL_CREATOR_ROLE = await securitizationManager.POOL_CREATOR();
    const transaction = await securitizationManager.grantRole(POOL_CREATOR_ROLE, poolCreatorSigner.address);
    await transaction.wait();
    await expect(transaction)
      .to.emit(securitizationManager, 'RoleGranted')
      .withArgs(POOL_CREATOR_ROLE, poolCreatorSigner.address, untangledAdminSigner.address);
  });
  describe('#newPoolInstance', async () => {
    it('Should create new pool instance', async function () {
      const minFirstLostCushion = 10 * RATE_SCALING_FACTOR;

      const transaction = await securitizationManager
        .connect(poolCreatorSigner)
        .newPoolInstance(stableCoin.address, minFirstLostCushion);
      const receipt = await transaction.wait();
      const [securitizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;
      expect(securitizationPoolAddress).to.be.properAddress;

      securitizationPoolContract = await ethers.getContractAt('SecuritizationPool', securitizationPoolAddress);
      expect(await securitizationPoolContract.underlyingCurrency()).to.equal(stableCoin.address);
      expect(await securitizationPoolContract.minFirstLossCushion()).to.equal(minFirstLostCushion);
      expect(await securitizationManager.isExistingPools(securitizationPoolAddress)).to.equal(true);
      expect(
        await securitizationPoolContract.hasRole(
          await securitizationPoolContract.OWNER_ROLE(),
          poolCreatorSigner.address
        )
      ).to.equal(true);
    });

    it('revert if minFistLossCushion >= 100%', async () => {
      const minFirstLostCushion = 101 * RATE_SCALING_FACTOR;

      await expect(
        securitizationManager.connect(poolCreatorSigner).newPoolInstance(stableCoin.address, minFirstLostCushion)
      ).to.be.revertedWith(`minFirstLossCushion is greater than 100`);
    });

    it('only pool creator role can create pool', async () => {
      await expect(
        securitizationManager.connect(lenderSigner).newPoolInstance(stableCoin.address, '100000')
      ).to.be.revertedWith(
        `AccessControl: account ${lenderSigner.address.toLowerCase()} is missing role 0x3e9c05fb0f9da4414e033bb9bf190a6e2072adf7e3077394fce683220513b8d7`
      );
    });
  });
  describe('#setUpTGEForSOT', async () => {
    let mintedIncreasingInterestTGE;

    it('Should set up TGE for SOT successfully', async () => {
      const tokenDecimals = 18;

      const openingTime = dayjs(new Date()).unix();
      const closingTime = dayjs(new Date()).add(7, 'days').unix();
      const rate = 2;
      const totalCapOfToken = parseEther('100000');
      const initialInterest = 100000;
      const finalInterest = 100000;
      const timeInterval = 1 * 24 * 3600; // seconds
      const amountChangeEachInterval = 0;
      const prefixOfNoteTokenSaleName = 'SOT_';

      const transaction = await securitizationManager
        .connect(poolCreatorSigner)
        .setUpTGEForSOT(
          untangledAdminSigner.address,
          securitizationPoolContract.address,
          [SaleType.MINTED_INCREASING_INTEREST, tokenDecimals],
          true,
          initialInterest,
          finalInterest,
          timeInterval,
          amountChangeEachInterval,
          { openingTime: openingTime, closingTime: closingTime, rate: rate, cap: totalCapOfToken },
          prefixOfNoteTokenSaleName
        );

      const receipt = await transaction.wait();

      const [tgeAddress] = receipt.events.find((e) => e.event == 'NewTGECreated').args;
      expect(tgeAddress).to.be.properAddress;

      mintedIncreasingInterestTGE = await ethers.getContractAt('MintedIncreasingInterestTGE', tgeAddress);

      const [sotToken] = receipt.events.find((e) => e.event == 'NewNotesTokenCreated').args;
      expect(sotToken).to.be.properAddress;
    });

    it('Should buy tokens successfully', async () => {
      await stableCoin.connect(lenderSigner).approve(mintedIncreasingInterestTGE.address, unlimitedAllowance);

      await securitizationManager
        .connect(lenderSigner)
        .buyTokens(mintedIncreasingInterestTGE.address, parseEther('100'));
    });
  });

  describe('#setUpTGEForJOT', async () => {
    it('Should set up TGE for JOT successfully', async () => {
      const tokenDecimals = 18;

      const openingTime = dayjs(new Date()).unix();
      const closingTime = dayjs(new Date()).add(7, 'days').unix();
      const rate = 2;
      const totalCapOfToken = parseEther('100000');
      const prefixOfNoteTokenSaleName = 'JOT_';

      // JOT only has SaleType.NORMAL_SALE
      await securitizationManager
        .connect(poolCreatorSigner)
        .setUpTGEForJOT(
          untangledAdminSigner.address,
          securitizationPoolContract.address,
          [SaleType.NORMAL_SALE, tokenDecimals],
          true,
          { openingTime: openingTime, closingTime: closingTime, rate: rate, cap: totalCapOfToken },
          prefixOfNoteTokenSaleName
        );
    });
  });
});
