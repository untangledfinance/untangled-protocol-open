const { ethers, getChainId } = require('hardhat');
const { expect } = require('chai');
const { BigNumber } = require('ethers');
const { parseEther, parseUnits, formatEther, formatBytes32String } = ethers.utils;
const dayjs = require('dayjs');
const _ = require('lodash');
const { time } = require('@nomicfoundation/hardhat-network-helpers');
const { setup } = require('../setup');
const { presignedMintMessage } = require('../shared/uid-helper');

const ONE_DAY_IN_SECONDS = 86400;

describe('MinFirstLoss', () => {
  let stableCoin;
  let securitizationManager;
  let uniqueIdentity;
  let jotContract;
  let sotContract;

  // Wallets
  let untangledAdminSigner,
    poolCreatorSigner,
    poolACreator,
    originatorSigner,
    lenderSigner,
    secondLenderSigner,
    relayer;

  const stableCoinAmountToBuyJOT = parseEther('1');
  const stableCoinAmountToBuySOT = parseEther('9');

  before('create fixture', async () => {
    // Init wallets
    [
      untangledAdminSigner,
      poolCreatorSigner,
      poolACreator,
      originatorSigner,
      lenderSigner,
      secondLenderSigner,
      relayer,
    ] = await ethers.getSigners();

    // Init contracts
    ({ stableCoin, uniqueIdentity, securitizationManager } = await setup());

    const POOL_CREATOR_ROLE = await securitizationManager.POOL_CREATOR();
    await securitizationManager.grantRole(POOL_CREATOR_ROLE, poolCreatorSigner.address);
    // Create new pool
    const transaction = await securitizationManager
      .connect(poolCreatorSigner)
      .newPoolInstance(stableCoin.address, '100000');
    const receipt = await transaction.wait();
    const [securitizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;

    securitizationPoolContract = await ethers.getContractAt('SecuritizationPool', securitizationPoolAddress);

    // Grant role originator
    const ORIGINATOR_ROLE = await securitizationPoolContract.ORIGINATOR_ROLE();
    await securitizationPoolContract.connect(poolCreatorSigner).grantRole(ORIGINATOR_ROLE, originatorSigner.address);

    // Init JOT sale
    const jotCap = parseEther('1000'); // $1000
    const isLongSaleTGEJOT = true;
    const now = dayjs().unix();
    const initialJotAmount = stableCoinAmountToBuyJOT;

    const setUpTGEJOTTransaction = await securitizationManager.connect(poolCreatorSigner).setUpTGEForJOT(
      poolCreatorSigner.address,
      securitizationPoolContract.address,
      initialJotAmount,
      [1, 2],
      isLongSaleTGEJOT,
      {
        openingTime: now,
        closingTime: now + ONE_DAY_IN_SECONDS,
        rate: 10000,
        cap: jotCap,
      },
      'Ticker'
    );
    const setUpTGEJOTReceipt = await setUpTGEJOTTransaction.wait();
    const [jotTGEAddress] = setUpTGEJOTReceipt.events.find((e) => e.event == 'NewTGECreated').args;
    mintedNormalTGEContract = await ethers.getContractAt('MintedNormalTGE', jotTGEAddress);
    const jotAddress = await securitizationPoolContract.jotToken();
    jotContract = await ethers.getContractAt('NoteToken', jotAddress);

    // Init SOT sale
    const sotCap = parseEther('1000'); // $1000
    const isLongSaleTGESOT = true;
    const setUpTGESOTTransaction = await securitizationManager.connect(poolCreatorSigner).setUpTGEForSOT(
      poolCreatorSigner.address,
      securitizationPoolContract.address,
      [0, 2],
      isLongSaleTGESOT,
      10000,
      90000,
      86400,
      10000,
      {
        openingTime: now,
        closingTime: now + 2 * ONE_DAY_IN_SECONDS,
        rate: 10000,
        cap: sotCap,
      },
      'Ticker'
    );
    const setUpTGESOTReceipt = await setUpTGESOTTransaction.wait();
    const [sotTGEAddress] = setUpTGESOTReceipt.events.find((e) => e.event == 'NewTGECreated').args;
    mintedIncreasingInterestTGEContract = await ethers.getContractAt('MintedIncreasingInterestTGE', sotTGEAddress);
    const sotAddress = await securitizationPoolContract.sotToken();
    sotContract = await ethers.getContractAt('NoteToken', sotAddress);

    // Lender gain UID
    const UID_TYPE = 0;
    const chainId = await getChainId();
    const expiredAt = now + ONE_DAY_IN_SECONDS;
    const nonce = 0;
    const ethRequired = parseEther('0.00083');
    const uidMintMessage = presignedMintMessage(
      lenderSigner.address,
      UID_TYPE,
      expiredAt,
      uniqueIdentity.address,
      nonce,
      chainId
    );
    const signature = await untangledAdminSigner.signMessage(uidMintMessage);
    await uniqueIdentity.connect(lenderSigner).mint(UID_TYPE, expiredAt, signature, { value: ethRequired });

    // Faucet stable coin to lender/investor
    await stableCoin.transfer(lenderSigner.address, parseEther('10000')); // $10k
  });

  describe('Check min first loss when buying tokens', () => {
    it('should revert if try to buy SOT when total JOT supply is 0 (zero JOT was sold)', async () => {
      // Lender buys SOT
      await stableCoin
        .connect(lenderSigner)
        .approve(mintedIncreasingInterestTGEContract.address, stableCoinAmountToBuySOT);

      await expect(
        securitizationManager
          .connect(lenderSigner)
          .buyTokens(mintedIncreasingInterestTGEContract.address, stableCoinAmountToBuySOT)
      ).to.be.revertedWith('Crowdsale: sale not started');
    });
    it('should revert if try to buy SOT with amount violates min first loss', async () => {
      // Lender buys JOT Token
      await stableCoin.connect(lenderSigner).approve(mintedNormalTGEContract.address, stableCoinAmountToBuyJOT);
      await securitizationManager
        .connect(lenderSigner)
        .buyTokens(mintedNormalTGEContract.address, stableCoinAmountToBuyJOT);
      // Lender try to buy SOT with amount violates min first loss
      const amountToBuySOT = stableCoinAmountToBuySOT.add(parseEther('1'));
      await stableCoin.connect(lenderSigner).approve(mintedIncreasingInterestTGEContract.address, amountToBuySOT);
      await expect(
        securitizationManager
          .connect(lenderSigner)
          .buyTokens(mintedIncreasingInterestTGEContract.address, amountToBuySOT)
      ).to.be.revertedWith('MinFirstLoss is not satisfied');
    });
    it('should buy SOT successfully if min first loss condition is satisfied', async () => {
      // Lender try to buy SOT with amount violates min first loss
      await stableCoin
        .connect(lenderSigner)
        .approve(mintedIncreasingInterestTGEContract.address, stableCoinAmountToBuySOT);
      await securitizationManager
        .connect(lenderSigner)
        .buyTokens(mintedIncreasingInterestTGEContract.address, stableCoinAmountToBuySOT);
    });
  });
});
