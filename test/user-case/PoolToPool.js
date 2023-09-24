const { ethers, getChainId } = require('hardhat');
const { expect } = require('chai');
const { setup } = require('../setup.js');
const { parseEther, parseUnits, formatEther, formatBytes32String } = ethers.utils;
const dayjs = require('dayjs');
const { time } = require('@nomicfoundation/hardhat-network-helpers');
const { presignedMintMessage } = require('../shared/uid-helper');

/**
 * This file tests the case that a pool invest into another pool
 * */

const ONE_DAY = 86400; // seconds
describe('Pool to Pool', () => {
  // investor pool - the pool which invest into another pool (buy JOT/SOT of another pool)
  describe.skip('Pool A invests in pool B', async () => {
    let stableCoin;
    let securitizationManager;
    let loanKernel;
    let loanRepaymentRouter;
    let loanAssetTokenContract;
    let loanRegistry;
    let uniqueIdentity;
    let registry;
    let loanInterestTermsContract;
    let distributionOperator;
    let distributionTranche;
    let poolBContract;
    let securitizationPoolValueService;

    // Wallets
    let untangledAdminSigner, poolCreatorSigner, poolACreator, borrowerSigner, lenderSigner, relayer, poolAPot;

    const stableCoinAmountToBuyJOT = parseEther('1'); // $1
    const stableCoinAmountToBuySOT = parseEther('2'); // $1
    const poolAPotInitialBalance = parseEther('100');
    let poolAContract;
    let mintedNormalTGEPoolBContract;
    let mintedIncreasingInterestTGEPoolBContract;
    let jotPoolBContract;
    let sotPoolBContract;
    let jotAmount;
    let sotAmount;
    before('init sale', async () => {
      // Init wallets
      [untangledAdminSigner, poolCreatorSigner, poolACreator, borrowerSigner, lenderSigner, relayer, poolAPot] =
        await ethers.getSigners();

      // Init contracts
      ({
        stableCoin,
        uniqueIdentity,
        loanAssetTokenContract,
        loanInterestTermsContract,
        loanRegistry,
        loanKernel,
        loanRepaymentRouter,
        securitizationManager,
        distributionOperator,
        distributionTranche,
        registry,
        securitizationPoolValueService,
      } = await setup());

      // Create new main pool
      const POOL_CREATOR_ROLE = await securitizationManager.POOL_CREATOR();
      await securitizationManager.grantRole(POOL_CREATOR_ROLE, poolCreatorSigner.address);
      const transaction = await securitizationManager
        .connect(poolCreatorSigner)
        .newPoolInstance(stableCoin.address, '100000');
      const receipt = await transaction.wait();
      const [securitizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;

      poolBContract = await ethers.getContractAt('SecuritizationPool', securitizationPoolAddress);
      // Init JOT sale
      const jotCap = '10000000000000000000';
      const isLongSaleTGEJOT = true;
      const now = dayjs().unix();
      const initialJOTAmount = parseEther('1')
      const setUpTGEJOTTransaction = await securitizationManager.connect(poolCreatorSigner).setUpTGEForJOT(
        poolCreatorSigner.address,
        poolBContract.address,
        initialJOTAmount,
        [1, 2],
        isLongSaleTGEJOT,
        {
          openingTime: now,
          closingTime: now + ONE_DAY,
          rate: 10000,
          cap: jotCap,
        },
        'Ticker'
      );
      const setUpTGEJOTReceipt = await setUpTGEJOTTransaction.wait();
      const [jotTGEAddress] = setUpTGEJOTReceipt.events.find((e) => e.event == 'NewTGECreated').args;
      mintedNormalTGEPoolBContract = await ethers.getContractAt('MintedNormalTGE', jotTGEAddress);

      // Init SOT sale
      const sotCap = '10000000000000000000';
      const isLongSaleTGESOT = true;
      const setUpTGESOTTransaction = await securitizationManager.connect(poolCreatorSigner).setUpTGEForSOT(
        poolCreatorSigner.address,
        poolBContract.address,
        [0, 2],
        isLongSaleTGESOT,
        10000,
        90000,
        86400,
        10000,
        {
          openingTime: now,
          closingTime: now + 2 * ONE_DAY,
          rate: 10000,
          cap: sotCap,
        },
        'Ticker'
      );
      const setUpTGESOTReceipt = await setUpTGESOTTransaction.wait();
      const [sotTGEAddress] = setUpTGESOTReceipt.events.find((e) => e.event == 'NewTGECreated').args;
      mintedIncreasingInterestTGEPoolBContract = await ethers.getContractAt(
        'MintedIncreasingInterestTGE',
        sotTGEAddress
      );

      // Create investor pool
      await securitizationManager.grantRole(POOL_CREATOR_ROLE, poolACreator.address);
      const poolACreationTransaction = await securitizationManager
        .connect(poolACreator)
        .newPoolInstance(stableCoin.address, '100000');
      const poolACreationReceipt = await poolACreationTransaction.wait();
      const [poolAContractAddress] = poolACreationReceipt.events.find((e) => e.event == 'NewPoolCreated').args;
      poolAContract = await ethers.getContractAt('SecuritizationPool', poolAContractAddress);
      await poolAContract.connect(poolACreator).setPot(poolAPot.address);

      // Pool A pot gain UID
      const UID_TYPE = 0;
      const chainId = await getChainId();
      const expiredAt = now + ONE_DAY;
      const nonce = 0;
      const ethRequired = parseEther('0.00083');
      const uidMintMessage = presignedMintMessage(
        poolAPot.address,
        UID_TYPE,
        expiredAt,
        uniqueIdentity.address,
        nonce,
        chainId
      );
      const signature = await untangledAdminSigner.signMessage(uidMintMessage);
      await uniqueIdentity.connect(poolAPot).mint(UID_TYPE, expiredAt, signature, { value: ethRequired });

      // Faucet stable coin to investorPoolPot
      await stableCoin.transfer(poolAPot.address, poolAPotInitialBalance); // $100
    });

    it('Pool A pot invests into pool B for JOT', async () => {
      // Invest into main pool (buy JOT token)
      await stableCoin.connect(poolAPot).approve(mintedNormalTGEPoolBContract.address, stableCoinAmountToBuyJOT);
      await securitizationManager
        .connect(poolAPot)
        .buyTokens(mintedNormalTGEPoolBContract.address, stableCoinAmountToBuyJOT);
      expect(await stableCoin.balanceOf(poolAPot.address)).equal(
        poolAPotInitialBalance.sub(stableCoinAmountToBuyJOT).toString()
      );
    });
    it('Pool A originator can transfer JOT from pool A pot to pool A', async () => {
      // Transfer to pool
      const jotPoolBAddress = await poolBContract.jotToken();
      jotPoolBContract = await ethers.getContractAt('NoteToken', jotPoolBAddress);
      jotAmount = await jotPoolBContract.balanceOf(poolAPot.address);
      const ORIGINATOR_ROLE = await poolAContract.ORIGINATOR_ROLE();
      await poolAContract.connect(poolACreator).grantRole(ORIGINATOR_ROLE, borrowerSigner.address);
      await jotPoolBContract.connect(poolAPot).approve(poolAContract.address, jotAmount);
      await poolAContract
        .connect(borrowerSigner)
        .collectERC20Assets([jotPoolBAddress], [poolAPot.address], [jotAmount]);
      expect(await jotPoolBContract.balanceOf(poolAContract.address)).equal(jotAmount);
    });
    it('Should include B JOT token value in pool A expected assets', async () => {
      // Check values
      const chainTime = await time.latest();
      const expectAssetValue = await securitizationPoolValueService.getExpectedAssetsValue(
        poolAContract.address,
        chainTime
      );
      expect(expectAssetValue).equal(stableCoinAmountToBuyJOT);
      const tokenERC20AssetAddress = await poolAContract.tokenAssetAddresses(0);
      expect(tokenERC20AssetAddress).equal(jotPoolBContract.address);
    });
    it('Pool A owner can claim B JOT Token from pool A to pool A pot', async () => {
      // Claim back to investor pot wallet
      await poolAContract
        .connect(poolACreator)
        .withdrawERC20Assets([jotPoolBContract.address], [poolAPot.address], [jotAmount]);
      const investorPoolPotJotBalance = await jotPoolBContract.balanceOf(poolAPot.address);
      expect(investorPoolPotJotBalance).equal('100');
    });
    it('Pool A pot can make JOT redeem request to pool B', async () => {
      // Redeem
      const investorPoolPotJotBalance = await jotPoolBContract.balanceOf(poolAPot.address);
      await jotPoolBContract.connect(poolAPot).approve(distributionTranche.address, investorPoolPotJotBalance);
      await distributionOperator
        .connect(poolAPot)
        .makeRedeemRequestAndRedeem(poolBContract.address, jotPoolBContract.address, '100');
      const investorPoolPotJotBalanceAfterRedeem = await jotPoolBContract.balanceOf(poolAPot.address);
      const investorPoolPotStableCoinBalanceAfterRedeem = await stableCoin.balanceOf(poolAPot.address);
      expect(investorPoolPotStableCoinBalanceAfterRedeem).equal(poolAPotInitialBalance);
      expect(investorPoolPotJotBalanceAfterRedeem).equal('0');
    });

    it('Pool A pot invests into pool B for SOT', async () => {
      // Invest into main pool (buy JOT token)
      await stableCoin.connect(poolAPot).approve(mintedNormalTGEPoolBContract.address, stableCoinAmountToBuyJOT);
      await securitizationManager
        .connect(poolAPot)
        .buyTokens(mintedNormalTGEPoolBContract.address, stableCoinAmountToBuyJOT);
      const value =await mintedIncreasingInterestTGEPoolBContract.hasStarted();
      // Invest into main pool (buy SOT token)
      await stableCoin
        .connect(poolAPot)
        .approve(mintedIncreasingInterestTGEPoolBContract.address, stableCoinAmountToBuySOT);
      await securitizationManager
        .connect(poolAPot)
        .buyTokens(mintedIncreasingInterestTGEPoolBContract.address, stableCoinAmountToBuySOT);
      expect(await stableCoin.balanceOf(poolAPot.address)).equal(
        poolAPotInitialBalance.sub(stableCoinAmountToBuySOT).sub(stableCoinAmountToBuyJOT).toString()
      );
    });
    it('Pool A originator can transfer SOT from pool A pot to pool A', async () => {
      // Transfer to pool
      const sotPoolBAddress = await poolBContract.sotToken();
      sotPoolBContract = await ethers.getContractAt('NoteToken', sotPoolBAddress);
      sotAmount = await sotPoolBContract.balanceOf(poolAPot.address);
      const ORIGINATOR_ROLE = await poolAContract.ORIGINATOR_ROLE();
      await poolAContract.connect(poolACreator).grantRole(ORIGINATOR_ROLE, borrowerSigner.address);
      await sotPoolBContract.connect(poolAPot).approve(poolAContract.address, sotAmount);
      await poolAContract
        .connect(borrowerSigner)
        .collectERC20Assets([sotPoolBAddress], [poolAPot.address], [sotAmount]);
      expect(await sotPoolBContract.balanceOf(poolAContract.address)).equal(sotAmount);
    });
    it('Should include B SOT token value in pool A expected assets', async () => {
      // Check values
      const chainTime = await time.latest();
      const expectAssetValue = await securitizationPoolValueService.getExpectedAssetsValue(
        poolAContract.address,
        chainTime
      );
      expect(expectAssetValue).equal(stableCoinAmountToBuySOT);
      const tokenERC20AssetAddress = await poolAContract.tokenAssetAddresses(1);
      expect(tokenERC20AssetAddress).equal(sotPoolBContract.address);
    });
    it('Pool A owner can claim B SOT Token from pool A to pool A pot', async () => {
      // Claim back to investor pot wallet
      await poolAContract
        .connect(poolACreator)
        .withdrawERC20Assets([sotPoolBContract.address], [poolAPot.address], [sotAmount]);
      const investorPoolPotJotBalance = await sotPoolBContract.balanceOf(poolAPot.address);
      expect(investorPoolPotJotBalance).equal('200');
    });
    it('Pool A pot can make SOT redeem request to pool B', async () => {
      // Redeem
      const investorPoolPotSotBalance = await sotPoolBContract.balanceOf(poolAPot.address);
      await sotPoolBContract.connect(poolAPot).approve(distributionTranche.address, investorPoolPotSotBalance);
      await distributionOperator
        .connect(poolAPot)
        .makeRedeemRequestAndRedeem(poolBContract.address, sotPoolBContract.address, investorPoolPotSotBalance);
      const investorPoolPotJotBalanceAfterRedeem = await sotPoolBContract.balanceOf(poolAPot.address);
      const investorPoolPotStableCoinBalanceAfterRedeem = await stableCoin.balanceOf(poolAPot.address);
      expect(investorPoolPotStableCoinBalanceAfterRedeem).equal(poolAPotInitialBalance.sub(stableCoinAmountToBuyJOT));
      expect(investorPoolPotJotBalanceAfterRedeem).equal('0');
    });
  });

  describe('Pool A invests in pool B, pool B invests in pool C', async () => {
    let stableCoin;
    let securitizationManager;
    let loanKernel;
    let loanRepaymentRouter;
    let loanAssetTokenContract;
    let loanRegistry;
    let uniqueIdentity;
    let registry;
    let loanInterestTermsContract;
    let distributionOperator;
    let distributionTranche;
    let distributionAssessor;
    let securitizationPoolValueService;

    let poolAContract;
    let poolBContract;
    let poolCContract;
    let mintedNormalTGEPoolBContract;
    let mintedIncreasingInterestTGEPoolBContract;
    let mintedNormalTGEPoolCContract;
    let mintedIncreasingInterestTGEPoolCContract;
    let sotBContract;
    let sotCContract;
    let jotBContract;
    let jotCContract;
    let sotAmountABuyFromB; // Currency amount
    let sotAmountBBuyFromC; // Currency amount

    // Wallets
    let untangledAdminSigner,
      poolBCreatorSigner,
      poolACreatorSigner,
      poolCCreatorSigner,
      poolAOriginatorSigner,
      poolBOriginatorSigner,
      lenderSigner,
      relayer,
      poolAPotSigner,
      poolBPotSigner,
      poolCPotSigner;

    const stableCoinAmountToBuyBSOT = parseEther('2'); // $2
    const stableCoinAmountToBuyCSOT = parseEther('1'); // $1
    const poolAPotInitialBalance = parseEther('100');
    const expectSOTAmountABuyFromB = '200';
    const expectSOTAmountBBuyFromC = '100';
    const NOW = dayjs().unix();
    before('init sale', async () => {
      const chainId = await getChainId();
      // Init wallets
      [
        untangledAdminSigner,
        poolBCreatorSigner,
        poolACreatorSigner,
        poolCCreatorSigner,
        poolAOriginatorSigner,
        poolBOriginatorSigner,
        lenderSigner,
        relayer,
        poolAPotSigner,
        poolBPotSigner,
        poolCPotSigner,
      ] = await ethers.getSigners();

      // Init contracts
      ({
        stableCoin,
        uniqueIdentity,
        loanAssetTokenContract,
        loanInterestTermsContract,
        loanRegistry,
        loanKernel,
        loanRepaymentRouter,
        securitizationManager,
        distributionOperator,
        distributionTranche,
        distributionAssessor,
        registry,
        securitizationPoolValueService,
      } = await setup());

      // Get constants
      const POOL_CREATOR_ROLE = await securitizationManager.POOL_CREATOR();

      // Create pool C
      await securitizationManager.grantRole(POOL_CREATOR_ROLE, poolCCreatorSigner.address);
      const poolCCreationTransaction = await securitizationManager
        .connect(poolCCreatorSigner)
        .newPoolInstance(stableCoin.address, '100000');
      const poolCCreationReceipt = await poolCCreationTransaction.wait();
      const [poolCContractAddress] = poolCCreationReceipt.events.find((e) => e.event == 'NewPoolCreated').args;
      poolCContract = await ethers.getContractAt('SecuritizationPool', poolCContractAddress);

      // Set pot for pool C
      await poolCContract.connect(poolCCreatorSigner).setPot(poolCPotSigner.address);
      await stableCoin.connect(poolCPotSigner).approve(poolCContract.address, ethers.constants.MaxUint256);

      // Init JOT sale pool C
      const jotCapPoolC = '10000000000000000000';
      const isLongSaleTGEJOTPoolC = true;
      const initialJOTAmountPoolC = parseEther('1');
      const setUpTGEJOTTransactionPoolC = await securitizationManager.connect(poolCCreatorSigner).setUpTGEForJOT(
        poolCCreatorSigner.address,
        poolCContract.address,
        initialJOTAmountPoolC,
        [1, 2],
        isLongSaleTGEJOTPoolC,
        {
          openingTime: NOW,
          closingTime: NOW + ONE_DAY,
          rate: 10000,
          cap: jotCapPoolC,
        },
        'Ticker'
      );
      const setUpTGEJOTPoolCReceipt = await setUpTGEJOTTransactionPoolC.wait();
      const [jotTGEPoolCAddress] = setUpTGEJOTPoolCReceipt.events.find((e) => e.event == 'NewTGECreated').args;
      mintedNormalTGEPoolCContract = await ethers.getContractAt('MintedNormalTGE', jotTGEPoolCAddress);
      const jotPoolCAddress = await poolCContract.jotToken();
      jotCContract = await ethers.getContractAt('NoteToken', jotPoolCAddress);

      // Init SOT sale pool C
      const sotCapPoolC = '10000000000000000000';
      const isLongSaleTGESOTPoolC = true;
      const setUpTGESOTTransactionPoolC = await securitizationManager.connect(poolCCreatorSigner).setUpTGEForSOT(
        poolCCreatorSigner.address,
        poolCContract.address,
        [0, 2],
        isLongSaleTGESOTPoolC,
        10000,
        90000,
        86400,
        10000,
        {
          openingTime: NOW,
          closingTime: NOW + 2 * ONE_DAY,
          rate: 10000,
          cap: sotCapPoolC,
        },
        'Ticker'
      );
      const setUpTGESOTPoolCReceipt = await setUpTGESOTTransactionPoolC.wait();
      const [sotTGEPoolCAddress] = setUpTGESOTPoolCReceipt.events.find((e) => e.event == 'NewTGECreated').args;
      mintedIncreasingInterestTGEPoolCContract = await ethers.getContractAt(
        'MintedIncreasingInterestTGE',
        sotTGEPoolCAddress
      );
      const sotPoolCAddress = await poolCContract.sotToken();
      sotCContract = await ethers.getContractAt('NoteToken', sotPoolCAddress);

      // Create pool B
      await securitizationManager.grantRole(POOL_CREATOR_ROLE, poolBCreatorSigner.address);
      const transaction = await securitizationManager
        .connect(poolBCreatorSigner)
        .newPoolInstance(stableCoin.address, '100000');
      const receipt = await transaction.wait();
      const [securitizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;

      // Set pot for pool B
      poolBContract = await ethers.getContractAt('SecuritizationPool', securitizationPoolAddress);
      await poolBContract.connect(poolBCreatorSigner).setPot(poolBPotSigner.address);
      await stableCoin.connect(poolBPotSigner).approve(poolBContract.address, ethers.constants.MaxUint256);

      // Init JOT sale pool B
      const jotCapPoolB = '10000000000000000000';
      const isLongSaleTGEJOTPoolB = true;
      const initialJOTAmountPoolB = parseEther('1');
      const setUpTGEJOTTransactionPoolB = await securitizationManager.connect(poolBCreatorSigner).setUpTGEForJOT(
        poolBCreatorSigner.address,
        poolBContract.address,
        initialJOTAmountPoolB,
        [1, 2],
        isLongSaleTGEJOTPoolB,
        {
          openingTime: NOW,
          closingTime: NOW + ONE_DAY,
          rate: 10000,
          cap: jotCapPoolB,
        },
        'Ticker'
      );
      const setUpTGEJOTPoolBReceipt = await setUpTGEJOTTransactionPoolB.wait();
      const [jotTGEPoolBAddress] = setUpTGEJOTPoolBReceipt.events.find((e) => e.event == 'NewTGECreated').args;
      mintedNormalTGEPoolBContract = await ethers.getContractAt('MintedNormalTGE', jotTGEPoolBAddress);
      const jotPoolBAddress = await poolBContract.jotToken();
      jotBContract = await ethers.getContractAt('NoteToken', jotPoolBAddress);

      // Init SOT sale pool B
      const sotCapPoolB = '10000000000000000000';
      const isLongSaleTGESOTPoolB = true;
      const setUpTGESOTTransactionPoolB = await securitizationManager.connect(poolBCreatorSigner).setUpTGEForSOT(
        poolBCreatorSigner.address,
        poolBContract.address,
        [0, 2],
        isLongSaleTGESOTPoolB,
        10000,
        90000,
        86400,
        10000,
        {
          openingTime: NOW,
          closingTime: NOW + 2 * ONE_DAY,
          rate: 10000,
          cap: sotCapPoolB,
        },
        'Ticker'
      );
      const setUpTGESOTPoolBReceipt = await setUpTGESOTTransactionPoolB.wait();
      const [sotTGEPoolBAddress] = setUpTGESOTPoolBReceipt.events.find((e) => e.event == 'NewTGECreated').args;
      mintedIncreasingInterestTGEPoolBContract = await ethers.getContractAt(
        'MintedIncreasingInterestTGE',
        sotTGEPoolBAddress
      );
      const sotPoolBAddress = await poolBContract.sotToken();
      sotBContract = await ethers.getContractAt('NoteToken', sotPoolBAddress);

      // Create pool A
      await securitizationManager.grantRole(POOL_CREATOR_ROLE, poolACreatorSigner.address);
      const poolACreationTransaction = await securitizationManager
        .connect(poolACreatorSigner)
        .newPoolInstance(stableCoin.address, '100000');
      const poolACreationReceipt = await poolACreationTransaction.wait();
      const [poolAContractAddress] = poolACreationReceipt.events.find((e) => e.event == 'NewPoolCreated').args;
      poolAContract = await ethers.getContractAt('SecuritizationPool', poolAContractAddress);
      await poolAContract.connect(poolACreatorSigner).setPot(poolAPotSigner.address);

      // Pool A pot gain UID
      const SIGNATURE_EXPIRE_TIME = NOW + ONE_DAY;
      const UID_TYPE = 0;
      const nonce = 0;
      const ethRequired = parseEther('0.00083');
      const uidMintMessagePotA = presignedMintMessage(
        poolAPotSigner.address,
        UID_TYPE,
        SIGNATURE_EXPIRE_TIME,
        uniqueIdentity.address,
        nonce,
        chainId
      );
      const signaturePotA = await untangledAdminSigner.signMessage(uidMintMessagePotA);
      await uniqueIdentity
        .connect(poolAPotSigner)
        .mint(UID_TYPE, SIGNATURE_EXPIRE_TIME, signaturePotA, { value: ethRequired });

      // Pool B pot gain UID
      const uidMintMessagePotB = presignedMintMessage(
        poolBPotSigner.address,
        UID_TYPE,
        SIGNATURE_EXPIRE_TIME,
        uniqueIdentity.address,
        nonce,
        chainId
      );
      const signaturePotB = await untangledAdminSigner.signMessage(uidMintMessagePotB);
      await uniqueIdentity
        .connect(poolBPotSigner)
        .mint(UID_TYPE, SIGNATURE_EXPIRE_TIME, signaturePotB, { value: ethRequired });

      // Faucet stable coin to investorPoolPot
      await stableCoin.transfer(poolAPotSigner.address, poolAPotInitialBalance); // $100
    });

    it('Pool A pot invests into pool B for SOT', async () => {
      // Invest into main pool (buy JOT token)
      await stableCoin
        .connect(poolAPotSigner)
        .approve(mintedNormalTGEPoolBContract.address, stableCoinAmountToBuyBSOT);
      await securitizationManager
        .connect(poolAPotSigner)
        .buyTokens(mintedNormalTGEPoolBContract.address, stableCoinAmountToBuyBSOT);
      expect(await stableCoin.balanceOf(poolAPotSigner.address)).equal(
        poolAPotInitialBalance.sub(stableCoinAmountToBuyBSOT).toString()
      );
      expect(await jotBContract.balanceOf(poolAPotSigner.address)).equal('200');
    });
    it('Pool B pot invests into pool C for SOT', async () => {
      await stableCoin
        .connect(poolBPotSigner)
        .approve(mintedNormalTGEPoolCContract.address, stableCoinAmountToBuyCSOT);
      await securitizationManager
        .connect(poolBPotSigner)
        .buyTokens(mintedNormalTGEPoolCContract.address, stableCoinAmountToBuyCSOT);
      expect(await stableCoin.balanceOf(poolBPotSigner.address)).equal(
        stableCoinAmountToBuyBSOT.sub(stableCoinAmountToBuyCSOT)
      );
      expect(await jotCContract.balanceOf(poolBPotSigner.address)).equal('100');
    });
    it('Pool A originator can transfer B-SOT from pool A pot to pool A', async () => {
      // Transfer to pool
      sotAmountABuyFromB = await jotBContract.balanceOf(poolAPotSigner.address);
      const ORIGINATOR_ROLE = await poolAContract.ORIGINATOR_ROLE();
      await poolAContract.connect(poolACreatorSigner).grantRole(ORIGINATOR_ROLE, poolAOriginatorSigner.address);
      await jotBContract.connect(poolAPotSigner).approve(poolAContract.address, sotAmountABuyFromB);
      await poolAContract
        .connect(poolAOriginatorSigner)
        .collectERC20Assets([jotBContract.address], [poolAPotSigner.address], [sotAmountABuyFromB]);
      expect(await jotBContract.balanceOf(poolAContract.address)).equal(sotAmountABuyFromB);
    });
    it('Pool B originator can transfer C-SOT from pool B pot to pool B', async () => {
      // Transfer to pool
      sotAmountBBuyFromC = await jotCContract.balanceOf(poolBPotSigner.address);
      const ORIGINATOR_ROLE = await poolBContract.ORIGINATOR_ROLE();
      await poolBContract.connect(poolBCreatorSigner).grantRole(ORIGINATOR_ROLE, poolBOriginatorSigner.address);
      await jotCContract.connect(poolBPotSigner).approve(poolBContract.address, sotAmountBBuyFromC);
      await poolBContract
        .connect(poolBOriginatorSigner)
        .collectERC20Assets([jotCContract.address], [poolBPotSigner.address], [sotAmountBBuyFromC]);
      expect(await jotCContract.balanceOf(poolBContract.address)).equal(sotAmountBBuyFromC);
    });
    it('Should include B-SOT token value in pool A expected assets', async () => {
      // Check values
      const chainTime = await time.latest();
      const expectAssetValue = await securitizationPoolValueService.getExpectedAssetsValue(
        poolAContract.address,
        chainTime
      );
      expect(expectAssetValue).closeTo(parseEther('3'), parseEther('0.01'));
      // SOT address was added to tokenAssetAddresses variables
      const tokenERC20AssetAddress = await poolAContract.tokenAssetAddresses(0);
      expect(tokenERC20AssetAddress).equal(jotBContract.address);
    });
    it('Should include C-SOT token value in pool B expected assets', async () => {
      // Check values
      const chainTime = await time.latest();
      // SOT address was added to tokenAssetAddresses variables
      const tokenERC20AssetAddress = await poolBContract.tokenAssetAddresses(0);
      expect(tokenERC20AssetAddress).equal(jotCContract.address);
      const expectAssetValue = await securitizationPoolValueService.getExpectedAssetsValue(
        poolBContract.address,
        chainTime
      );
      expect(expectAssetValue).equal(stableCoinAmountToBuyCSOT);
    });
    it('Pool A owner can claim B-SOT Token from pool A to pool A pot', async () => {
      // Claim back to investor pot wallet
      await poolAContract
        .connect(poolACreatorSigner)
        .withdrawERC20Assets([jotBContract.address], [poolAPotSigner.address], [sotAmountABuyFromB]);
      const sotBalance = await jotBContract.balanceOf(poolAPotSigner.address);
      expect(sotBalance).equal(expectSOTAmountABuyFromB);
    });
    it('Pool B owner can claim C-SOT Token from pool B to pool B pot', async () => {
      // Claim back to investor pot wallet
      await poolBContract
        .connect(poolBCreatorSigner)
        .withdrawERC20Assets([jotCContract.address], [poolBPotSigner.address], [sotAmountBBuyFromC]);
      const sotBalance = await jotCContract.balanceOf(poolBPotSigner.address);
      expect(sotBalance).equal(expectSOTAmountBBuyFromC);
    });
    it('Pool B pot can make SOT redeem request to pool C', async () => {
      // Redeem
      const sotBalance = await jotCContract.balanceOf(poolBPotSigner.address);
      await jotCContract.connect(poolBPotSigner).approve(distributionTranche.address, sotBalance);

      await distributionOperator
        .connect(poolBPotSigner)
        .makeRedeemRequestAndRedeem(poolCContract.address, jotCContract.address, sotBalance);
      const investorPoolPotJotBalanceAfterRedeem = await jotCContract.balanceOf(poolBPotSigner.address);
      const investorPoolPotStableCoinBalanceAfterRedeem = await stableCoin.balanceOf(poolBPotSigner.address);
      expect(investorPoolPotStableCoinBalanceAfterRedeem).equal(stableCoinAmountToBuyBSOT);
      expect(investorPoolPotJotBalanceAfterRedeem).equal('0');
    });

    it('Pool A pot can make SOT redeem request to pool B', async () => {
      // Redeem
      const investorPoolPotSotBalance = await jotBContract.balanceOf(poolAPotSigner.address);
      await jotBContract.connect(poolAPotSigner).approve(distributionTranche.address, investorPoolPotSotBalance);

      await distributionOperator
        .connect(poolAPotSigner)
        .makeRedeemRequestAndRedeem(poolBContract.address, jotBContract.address, investorPoolPotSotBalance);
      const investorPoolPotJotBalanceAfterRedeem = await jotBContract.balanceOf(poolAPotSigner.address);
      const investorPoolPotStableCoinBalanceAfterRedeem = await stableCoin.balanceOf(poolAPotSigner.address);
      expect(investorPoolPotStableCoinBalanceAfterRedeem).closeTo(poolAPotInitialBalance, parseEther('0.01'));
      expect(investorPoolPotJotBalanceAfterRedeem).equal('0');
    });
  });
});
