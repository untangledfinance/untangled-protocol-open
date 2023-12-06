const { ethers, getChainId } = require('hardhat');
const { expect } = require('chai');
const { BigNumber, utils } = require('ethers');
const { parseEther } = ethers.utils;

const dayjs = require('dayjs');
const { time } = require('@nomicfoundation/hardhat-network-helpers');
const { setup } = require('../setup');
const { presignedMintMessage } = require('../shared/uid-helper');
const { POOL_ADMIN_ROLE, ORIGINATOR_ROLE } = require('../constants.js');
const { getPoolByAddress } = require('../utils');

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

    await securitizationManager.grantRole(POOL_ADMIN_ROLE, poolCreatorSigner.address);
    // Create new pool
    const transaction = await securitizationManager
      .connect(poolCreatorSigner)

      .newPoolInstance(
        utils.keccak256(Date.now()),

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
              },
              {
                name: 'debtCeiling',
                type: 'uint256',
              },

            ]
          }
        ], [
          {
            currency: stableCoin.address,
            minFirstLossCushion: '100000',
            validatorRequired: true,
            debtCeiling: parseEther('1000').toString(),
          }
        ]));

    const receipt = await transaction.wait();
    const [securitizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;

    securitizationPoolContract = await getPoolByAddress(securitizationPoolAddress);

    // Grant role originator
    await securitizationPoolContract.connect(poolCreatorSigner).grantRole(ORIGINATOR_ROLE, originatorSigner.address);

    // Init JOT sale
    const jotCap = parseEther('1000'); // $1000
    const isLongSaleTGEJOT = true;
    const now = dayjs().unix();
    const initialJotAmount = stableCoinAmountToBuyJOT;

    const setUpTGEJOTTransaction = await securitizationManager.connect(poolCreatorSigner).setUpTGEForJOT(
      {
        issuerTokenController: poolCreatorSigner.address,
        pool: securitizationPoolContract.address,
        minBidAmount: parseEther('1'),
        saleTypeAndDecimal: [1, 2],
        longSale: isLongSaleTGEJOT,
        ticker: 'Ticker',
      },
      {
        openingTime: now,
        closingTime: now + ONE_DAY_IN_SECONDS,
        rate: 10000,
        cap: jotCap,
      },
      initialJotAmount,
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
      {
        issuerTokenController: poolCreatorSigner.address,
        pool: securitizationPoolContract.address,
        minBidAmount: parseEther('1'),
        saleTypeAndDecimal: [0, 2],
        longSale: isLongSaleTGESOT,
        ticker: 'Ticker',
      },
      {
        openingTime: now,
        closingTime: now + 2 * ONE_DAY_IN_SECONDS,
        rate: 10000,
        cap: sotCap,
      },
      {
        initialInterest: 10000,
        finalInterest: 90000,
        timeInterval: 86400,
        amountChangeEachInterval: 10000,
      },
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
