const { ethers, getChainId } = require('hardhat');
const { expect } = require('../shared/expect.js');
const { mainFixture } = require('../shared/fixtures');
const { BigNumber } = require('ethers');
const { parseEther, parseUnits, formatEther, formatBytes32String } = ethers.utils;
const dayjs = require('dayjs');
const _ = require('lodash');
const { admin } = require('@openzeppelin/truffle-upgrades');
const { time, impersonateAccount, stopImpersonatingAccount, setBalance } = require('@nomicfoundation/hardhat-network-helpers');
const { parse } = require('dotenv');
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
  let distributionOperator;
  let distributionTranche;
  let securitizationPoolContract;
  let securitizationPoolValueService;

  // Wallets
  let untangledAdminSigner, poolCreatorSigner, investorPoolCreator, borrowerSigner, lenderSigner, relayer,
    investorPoolPot;

  before('create fixture', async () => {
    // Init wallets
    [untangledAdminSigner, poolCreatorSigner, investorPoolCreator, borrowerSigner, lenderSigner, relayer, investorPoolPot] =
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
      distributionOperator,
      distributionTranche,
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

    securitizationPoolContract = await ethers.getContractAt('SecuritizationPool', securitizationPoolAddress);
  });
  // investor pool - the pool which invest into another pool (buy JOT/SOT of another pool)
  it('should include note token asset in invest pool', async () => {
    // Init JOT sale
    const jotCap = '10000000000000000000';
    const isLongSaleTGEJOT = true;
    const now = dayjs().unix();
    const setUpTGEJOTTransaction = await securitizationManagerContract
      .connect(poolCreatorSigner)
      .setUpTGEForJOT(poolCreatorSigner.address, securitizationPoolContract.address, [1, 2], isLongSaleTGEJOT, {
        openingTime: now,
        closingTime: now + ONE_DAY,
        rate: 10000,
        cap: jotCap,
      }, 'Ticker');
    const setUpTGEJOTReceipt = await setUpTGEJOTTransaction.wait();
    const [jotTGEAddress] = setUpTGEJOTReceipt.events.find(e => e.event == 'NewTGECreated').args;
    const mintedNormalTGEContract = await ethers.getContractAt('MintedNormalTGE', jotTGEAddress);

    // Create investor pool
    const POOL_CREATOR_ROLE = await securitizationManagerContract.POOL_CREATOR();
    await securitizationManagerContract.grantRole(POOL_CREATOR_ROLE, investorPoolCreator.address);

    const transaction = await securitizationManagerContract
      .connect(investorPoolCreator)
      .newPoolInstance(stableCoin.address, '100000');
    const receipt = await transaction.wait();
    const [securitizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;

    const investorSecuritizationPoolContract = await ethers.getContractAt('SecuritizationPool', securitizationPoolAddress);
    await investorSecuritizationPoolContract.connect(investorPoolCreator).setPot(investorPoolPot.address)

    // Gain UID
    const UID_TYPE = 0
    const chainId = await getChainId();
    const expiredAt = now + ONE_DAY;
    const nonce = 0;
    const ethRequired = parseEther("0.00083")

    const uidMintMessage = presignedMintMessage(investorPoolPot.address, UID_TYPE, expiredAt, uniqueIdentityContract.address, nonce, chainId)
    const signature = await untangledAdminSigner.signMessage(uidMintMessage)
    await uniqueIdentityContract.connect(investorPoolPot).mint(UID_TYPE, expiredAt, signature, { value: ethRequired });

    // Faucet stable coin to investorPoolPot
    await stableCoin.transfer(investorPoolPot.address, parseEther('100')); // $100

    // Invest into main pool (buy JOT token)
    const stableCoinAmountToBuyJOT = parseEther('1'); // $1
    await stableCoin.connect(investorPoolPot).approve(mintedNormalTGEContract.address, stableCoinAmountToBuyJOT)
    await securitizationManagerContract.connect(investorPoolPot).buyTokens(mintedNormalTGEContract.address, stableCoinAmountToBuyJOT)

    // Check values
    const chainTime = await time.latest();
    const expectAssetValue = await securitizationPoolValueService.getExpectedAssetsValue(investorSecuritizationPoolContract.address, chainTime)
    console.log(expectAssetValue);
    console.log(await investorSecuritizationPoolContract.getTokenAssetAddresses())
  });


});