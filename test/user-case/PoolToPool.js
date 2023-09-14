const { ethers, getChainId } = require('hardhat');
const { expect } = require('../shared/expect.js');
const { mainFixture } = require('../shared/fixtures');
const { parseEther, parseUnits, formatEther, formatBytes32String } = ethers.utils;
const dayjs = require('dayjs');
const _ = require('lodash');
const { time, impersonateAccount, stopImpersonatingAccount, setBalance } = require('@nomicfoundation/hardhat-network-helpers');
const { presignedMintMessage } = require('../shared/uid-helper');

/**
 * This file tests the case that a pool invest into another pool
 * */

const ONE_DAY = 86400 // seconds
describe('Pool to Pool', () => {
  let stableCoin;
  let securitizationManagerContract;
  let loanKernelContract;
  let loanRepaymentRouterContract;
  let loanAssetTokenContract;
  let loanRegistryContract;
  let uniqueIdentityContract;
  let registryContract;
  let loanInterestTermsContract;
  let distributionOperatorContract;
  let distributionTrancheContract;
  let poolBContract;
  let securitizationPoolValueService;

  // Wallets
  let untangledAdminSigner, poolCreatorSigner, poolACreator, borrowerSigner, lenderSigner, relayer,
    poolAPot;

  before('create fixture', async () => {
    // Init wallets
    [untangledAdminSigner, poolCreatorSigner, poolACreator, borrowerSigner, lenderSigner, relayer, poolAPot] =
      await ethers.getSigners();

    // Init contracts
    ({
      stableCoin,
      uniqueIdentityContract,
      loanAssetTokenContract,
      loanInterestTermsContract,
      loanRegistryContract,
      loanKernelContract,
      loanRepaymentRouterContract,
      securitizationManagerContract,
      distributionOperatorContract,
      distributionTrancheContract,
      registryContract,
      securitizationPoolValueService
    } = await mainFixture());

    // Create new main pool
    const POOL_CREATOR_ROLE = await securitizationManagerContract.POOL_CREATOR();
    await securitizationManagerContract.grantRole(POOL_CREATOR_ROLE, poolCreatorSigner.address);
    const transaction = await securitizationManagerContract
      .connect(poolCreatorSigner)
      .newPoolInstance(stableCoin.address, '100000');
    const receipt = await transaction.wait();
    const [securitizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;

    poolBContract = await ethers.getContractAt('SecuritizationPool', securitizationPoolAddress);
  });
  // investor pool - the pool which invest into another pool (buy JOT/SOT of another pool)
  describe('Pool A invests in pool B', async () => {
    const stableCoinAmountToBuyJOT = parseEther('1'); // $1
    const stableCoinAmountToBuySOT = parseEther('2'); // $1
    const poolAPotInitialBalance = parseEther('100')
    let poolAContract;
    let mintedNormalTGEPoolBContract;
    let mintedIncreasingInterestTGEPoolBContract;
    let jotPoolBContract;
    let sotPoolBContract;
    let jotAmount;
    let sotAmount;
    before('init sale', async () => {
      // Init JOT sale
      const jotCap = '10000000000000000000';
      const isLongSaleTGEJOT = true;
      const now = dayjs().unix();
      const setUpTGEJOTTransaction = await securitizationManagerContract
        .connect(poolCreatorSigner)
        .setUpTGEForJOT(poolCreatorSigner.address, poolBContract.address, [1, 2], isLongSaleTGEJOT, {
          openingTime: now,
          closingTime: now + ONE_DAY,
          rate: 10000,
          cap: jotCap,
        }, 'Ticker');
      const setUpTGEJOTReceipt = await setUpTGEJOTTransaction.wait();
      const [jotTGEAddress] = setUpTGEJOTReceipt.events.find(e => e.event == 'NewTGECreated').args;
      mintedNormalTGEPoolBContract = await ethers.getContractAt('MintedNormalTGE', jotTGEAddress);

      // Init SOT sale
      const sotCap = '10000000000000000000';
      const isLongSaleTGESOT = true;
      const setUpTGESOTTransaction = await securitizationManagerContract.connect(poolCreatorSigner).setUpTGEForSOT(poolCreatorSigner.address, poolBContract.address, [0, 2], isLongSaleTGESOT, 10000, 90000, 86400, 10000, {
        openingTime: now,
        closingTime: now + 2 * ONE_DAY,
        rate: 10000,
        cap: sotCap,
      }, 'Ticker');
      const setUpTGESOTReceipt = await setUpTGESOTTransaction.wait();
      const [sotTGEAddress] = setUpTGESOTReceipt.events.find(e => e.event == 'NewTGECreated').args;
      mintedIncreasingInterestTGEPoolBContract = await ethers.getContractAt('MintedIncreasingInterestTGE', sotTGEAddress);

      // Create investor pool
      const POOL_CREATOR_ROLE = await securitizationManagerContract.POOL_CREATOR();
      await securitizationManagerContract.grantRole(POOL_CREATOR_ROLE, poolACreator.address);
      const transaction = await securitizationManagerContract
        .connect(poolACreator)
        .newPoolInstance(stableCoin.address, '100000');
      const receipt = await transaction.wait();
      const [securitizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;
      poolAContract = await ethers.getContractAt('SecuritizationPool', securitizationPoolAddress);
      await poolAContract.connect(poolACreator).setPot(poolAPot.address)

      // Pool A pot gain UID
      const UID_TYPE = 0
      const chainId = await getChainId();
      const expiredAt = now + ONE_DAY;
      const nonce = 0;
      const ethRequired = parseEther("0.00083")
      const uidMintMessage = presignedMintMessage(poolAPot.address, UID_TYPE, expiredAt, uniqueIdentityContract.address, nonce, chainId)
      const signature = await untangledAdminSigner.signMessage(uidMintMessage)
      await uniqueIdentityContract.connect(poolAPot).mint(UID_TYPE, expiredAt, signature, { value: ethRequired });

      // Faucet stable coin to investorPoolPot
      await stableCoin.transfer(poolAPot.address, poolAPotInitialBalance); // $100
    })

    it('Pool A pot invests into pool B', async () => {
      // Invest into main pool (buy JOT token)
      await stableCoin.connect(poolAPot).approve(mintedNormalTGEPoolBContract.address, stableCoinAmountToBuyJOT)
      await securitizationManagerContract.connect(poolAPot).buyTokens(mintedNormalTGEPoolBContract.address, stableCoinAmountToBuyJOT)
    });
    it('Pool A originator can transfer JOT from pool A pot to pool A', async () => {
      // Transfer to pool
      const jotPoolBAddress = await poolBContract.jotToken();
      jotPoolBContract = await ethers.getContractAt('NoteToken', jotPoolBAddress);
      jotAmount = await jotPoolBContract.balanceOf(poolAPot.address);
      const ORIGINATOR_ROLE = await poolAContract.ORIGINATOR_ROLE();
      await poolAContract.connect(poolACreator).grantRole(ORIGINATOR_ROLE, borrowerSigner.address);
      await jotPoolBContract.connect(poolAPot).approve(poolAContract.address, jotAmount);
      await poolAContract.connect(borrowerSigner).collectERC20Assets(
        [jotPoolBAddress],
        [poolAPot.address],
        [jotAmount]
      )
    });
    it('Should include B JOT token value in pool A expected assets', async () => {
      // Check values
      const chainTime = await time.latest();
      const expectAssetValue = await securitizationPoolValueService.getExpectedAssetsValue(poolAContract.address, chainTime)
      expect(expectAssetValue).equal(stableCoinAmountToBuyJOT)
      const tokenERC20AssetAddress = await poolAContract.tokenAssetAddresses(0);
      expect(tokenERC20AssetAddress).equal(jotPoolBContract.address);
    });
    it('Pool A owner can claim B JOT Token from pool A to pool A pot', async () => {
      // Claim back to investor pot wallet
      await poolAContract.connect(poolACreator).withdrawERC20Assets([jotPoolBContract.address], [poolAPot.address], [jotAmount])
      const investorPoolPotJotBalance = await jotPoolBContract.balanceOf(poolAPot.address);
      expect(investorPoolPotJotBalance).equal('100');
    });
    it('Pool A pot can make JOT redeem request to pool B', async () => {
      // Redeem
      const investorPoolPotJotBalance = await jotPoolBContract.balanceOf(poolAPot.address);
      await jotPoolBContract.connect(poolAPot).approve(distributionTrancheContract.address, investorPoolPotJotBalance);
      await distributionOperatorContract.connect(poolAPot).makeRedeemRequestAndRedeem(poolBContract.address, jotPoolBContract.address, '100')
      const investorPoolPotJotBalanceAfterRedeem = await jotPoolBContract.balanceOf(poolAPot.address);
      const investorPoolPotStableCoinBalanceAfterRedeem = await stableCoin.balanceOf(poolAPot.address);
      expect(investorPoolPotStableCoinBalanceAfterRedeem).equal(poolAPotInitialBalance);
      expect(investorPoolPotJotBalanceAfterRedeem).equal('0');
    });

    it('Pool A pot invests into pool B for SOT', async () => {
      // Invest into main pool (buy JOT token)
      await stableCoin.connect(poolAPot).approve(mintedIncreasingInterestTGEPoolBContract.address, stableCoinAmountToBuySOT)
      await securitizationManagerContract.connect(poolAPot).buyTokens(mintedIncreasingInterestTGEPoolBContract.address, stableCoinAmountToBuySOT)
    });
    it('Pool A originator can transfer SOT from pool A pot to pool A', async () => {
      // Transfer to pool
      const sotPoolBAddress = await poolBContract.sotToken();
      sotPoolBContract = await ethers.getContractAt('NoteToken', sotPoolBAddress);
      sotAmount = await sotPoolBContract.balanceOf(poolAPot.address);
      const ORIGINATOR_ROLE = await poolAContract.ORIGINATOR_ROLE();
      await poolAContract.connect(poolACreator).grantRole(ORIGINATOR_ROLE, borrowerSigner.address);
      await sotPoolBContract.connect(poolAPot).approve(poolAContract.address, sotAmount);
      await poolAContract.connect(borrowerSigner).collectERC20Assets(
        [sotPoolBAddress],
        [poolAPot.address],
        [sotAmount]
      )
    });
    it('Should include B SOT token value in pool A expected assets', async () => {
      // Check values
      const chainTime = await time.latest();
      const expectAssetValue = await securitizationPoolValueService.getExpectedAssetsValue(poolAContract.address, chainTime);
      expect(expectAssetValue).equal(stableCoinAmountToBuySOT);
      const tokenERC20AssetAddress = await poolAContract.tokenAssetAddresses(1);
      expect(tokenERC20AssetAddress).equal(sotPoolBContract.address);
    });
    it('Pool A owner can claim B SOT Token from pool A to pool A pot', async () => {
      // Claim back to investor pot wallet
      await poolAContract.connect(poolACreator).withdrawERC20Assets([sotPoolBContract.address], [poolAPot.address], [sotAmount])
      const investorPoolPotJotBalance = await sotPoolBContract.balanceOf(poolAPot.address);
      expect(investorPoolPotJotBalance).equal('200');
    });
    it('Pool A pot can make SOT redeem request to pool B', async () => {
      // Redeem
      const investorPoolPotSotBalance = await sotPoolBContract.balanceOf(poolAPot.address);
      await sotPoolBContract.connect(poolAPot).approve(distributionTrancheContract.address, investorPoolPotSotBalance);
      await distributionOperatorContract.connect(poolAPot).makeRedeemRequestAndRedeem(poolBContract.address, sotPoolBContract.address, investorPoolPotSotBalance);
      const investorPoolPotJotBalanceAfterRedeem = await sotPoolBContract.balanceOf(poolAPot.address);
      const investorPoolPotStableCoinBalanceAfterRedeem = await stableCoin.balanceOf(poolAPot.address);
      expect(investorPoolPotStableCoinBalanceAfterRedeem).equal(poolAPotInitialBalance);
      expect(investorPoolPotJotBalanceAfterRedeem).equal('0');
    });

  });

});