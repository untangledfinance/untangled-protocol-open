const { ethers, upgrades } = require('hardhat');
const { deployments } = require('hardhat');
const _ = require('lodash');
const dayjs = require('dayjs');
const { expect } = require('./shared/expect.js');
const { time } = require('@nomicfoundation/hardhat-network-helpers');

const { BigNumber } = ethers;
const { parseEther, parseUnits, formatEther, formatBytes32String } = ethers.utils;
const { presignedMintMessage } = require('./shared/uid-helper.js');

const {
  unlimitedAllowance,
  ZERO_ADDRESS,
  genLoanAgreementIds,
  saltFromOrderValues,
  debtorsFromOrderAddresses,
  packTermsContractParameters,
  interestRateFixedPoint,
  genSalt,
} = require('./utils.js');
const { setup } = require('./setup.js');
const { SaleType } = require('./shared/constants.js');

const ONE_DAY = 86400;
describe('SecuritizationPool', () => {
  let stableCoin;
  let loanAssetTokenContract;
  let loanInterestTermsContract;
  let loanKernel;
  let loanRepaymentRouter;
  let securitizationManager;
  let securitizationPoolContract;
  let secondSecuritizationPool;
  let tokenIds;
  let uniqueIdentity;
  let distributionOperator;
  let sotToken;
  let distributionTranche;
  let mintedIncreasingInterestTGE;

  // Wallets
  let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer;
  before('create fixture', async () => {
    [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer] =
      await ethers.getSigners();

    ({
      stableCoin,
      loanAssetTokenContract,
      loanInterestTermsContract,
      loanKernel,
      loanRepaymentRouter,
      securitizationManager,
      uniqueIdentity,
      distributionOperator,
      distributionTranche,
    } = await setup());

    await stableCoin.transfer(lenderSigner.address, parseEther('1000'));

    await stableCoin.connect(untangledAdminSigner).approve(loanRepaymentRouter.address, unlimitedAllowance);

    // Gain UID
    const UID_TYPE = 0;
    const chainId = await getChainId();
    const expiredAt = dayjs().unix() + 86400;
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
  });

  describe('#security pool', async () => {
    it('Create pool', async () => {
      const POOL_CREATOR_ROLE = await securitizationManager.POOL_CREATOR();
      await securitizationManager.grantRole(POOL_CREATOR_ROLE, poolCreatorSigner.address);
      // Create new pool
      let transaction = await securitizationManager
        .connect(poolCreatorSigner)
        .newPoolInstance(stableCoin.address, '100000');
      let receipt = await transaction.wait();
      let [securitizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;

      securitizationPoolContract = await ethers.getContractAt('SecuritizationPool', securitizationPoolAddress);
      await securitizationPoolContract
        .connect(poolCreatorSigner)
        .grantRole(await securitizationPoolContract.ORIGINATOR_ROLE(), originatorSigner.address);

      transaction = await securitizationManager
        .connect(poolCreatorSigner)
        .newPoolInstance(stableCoin.address, '100000');
      receipt = await transaction.wait();
      [securitizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;

      secondSecuritizationPool = await ethers.getContractAt('SecuritizationPool', securitizationPoolAddress);
      await secondSecuritizationPool
        .connect(poolCreatorSigner)
        .grantRole(await secondSecuritizationPool.ORIGINATOR_ROLE(), originatorSigner.address);

      const oneDayInSecs = 1 * 24 * 3600;
      const halfOfADay = oneDayInSecs / 2;

      const riskScore = {
        daysPastDue: oneDayInSecs,
        advanceRate: 950000,
        penaltyRate: 900000,
        interestRate: 910000,
        probabilityOfDefault: 800000,
        lossGivenDefault: 810000,
        gracePeriod: halfOfADay,
        collectionPeriod: halfOfADay,
        writeOffAfterGracePeriod: halfOfADay,
        writeOffAfterCollectionPeriod: halfOfADay,
      };
      const daysPastDues = [riskScore.daysPastDue];
      const ratesAndDefaults = [
        riskScore.advanceRate,
        riskScore.penaltyRate,
        riskScore.interestRate,
        riskScore.probabilityOfDefault,
        riskScore.lossGivenDefault,
      ];
      const periodsAndWriteOffs = [
        riskScore.gracePeriod,
        riskScore.collectionPeriod,
        riskScore.writeOffAfterGracePeriod,
        riskScore.writeOffAfterCollectionPeriod,
      ];

      await securitizationPoolContract
        .connect(poolCreatorSigner)
        .setupRiskScores(daysPastDues, ratesAndDefaults, periodsAndWriteOffs);
    });
  });

  describe('#Securitization Manager', async () => {
    it('Should set up TGE for SOT successfully', async () => {
      const tokenDecimals = 18;

      const openingTime = dayjs(new Date()).unix();
      const closingTime = dayjs(new Date()).add(7, 'days').unix();
      const rate = 2;
      const totalCapOfToken = parseEther('100000');
      const initialInterest = 10000;
      const finalInterest = 10000;
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

      const [sotTokenAddress] = receipt.events.find((e) => e.event == 'NewNotesTokenCreated').args;
      expect(sotTokenAddress).to.be.properAddress;

      sotToken = await ethers.getContractAt('NoteToken', sotTokenAddress);
    });

    it('Should buy tokens successfully', async () => {
      await stableCoin.connect(lenderSigner).approve(mintedIncreasingInterestTGE.address, unlimitedAllowance);

      await securitizationManager
        .connect(lenderSigner)
        .buyTokens(mintedIncreasingInterestTGE.address, parseEther('100'));

      const stablecoinBalanceOfPayerAfter = await stableCoin.balanceOf(lenderSigner.address);
      expect(formatEther(stablecoinBalanceOfPayerAfter)).equal('900.0');

      expect(formatEther(await stableCoin.balanceOf(securitizationPoolContract.address))).equal('100.0');
    });
  });

  describe('#Distribution Operator', async () => {
    it('makeRedeemRequestAndRedeem', async () => {
      await sotToken.connect(lenderSigner).approve(distributionTranche.address, unlimitedAllowance);
      await distributionOperator
        .connect(lenderSigner)
        .makeRedeemRequestAndRedeem(securitizationPoolContract.address, sotToken.address, parseEther('10'));

      expect(formatEther(await sotToken.balanceOf(lenderSigner.address))).equal('90.0');
    });
  });

  let expirationTimestamps;
  const CREDITOR_FEE = '0';
  const ASSET_PURPOSE = '0';
  const inputAmount = 10;
  const inputPrice = 15;
  const principalAmount = _.round(inputAmount * inputPrice * 100);

  describe('#LoanKernel', async () => {
    it('Execute fillDebtOrder successfully', async () => {
      const orderAddresses = [
        securitizationPoolContract.address,
        stableCoin.address,
        loanRepaymentRouter.address,
        loanInterestTermsContract.address,
        relayer.address,
        // borrower 1
        borrowerSigner.address,
        // borrower 2
        borrowerSigner.address,
      ];

      const riskScore = '50';
      expirationTimestamps = dayjs(new Date()).add(7, 'days').unix();

      const orderValues = [
        CREDITOR_FEE,
        ASSET_PURPOSE,
        // token 1
        parseEther(principalAmount.toString()),
        expirationTimestamps,
        genSalt(),
        riskScore,
        // token 2
        parseEther(principalAmount.toString()),
        expirationTimestamps,
        genSalt(),
        riskScore,
      ];

      const termInDaysLoan = 10;
      const interestRatePercentage = 5;
      const termsContractParameter = packTermsContractParameters({
        amortizationUnitType: 1,
        gracePeriodInDays: 2,
        principalAmount,
        termLengthUnits: _.ceil(termInDaysLoan * 24),
        interestRateFixedPoint: interestRateFixedPoint(interestRatePercentage),
      });

      const termsContractParameters = [termsContractParameter, termsContractParameter];

      const salts = saltFromOrderValues(orderValues, termsContractParameters.length);
      const debtors = debtorsFromOrderAddresses(orderAddresses, termsContractParameters.length);

      tokenIds = genLoanAgreementIds(
        loanRepaymentRouter.address,
        debtors,
        loanInterestTermsContract.address,
        termsContractParameters,
        salts
      );

      await loanKernel.fillDebtOrder(orderAddresses, orderValues, termsContractParameters, tokenIds);

      const ownerOfAgreement = await loanAssetTokenContract.ownerOf(tokenIds[0]);
      expect(ownerOfAgreement).equal(securitizationPoolContract.address);

      const balanceOfPool = await loanAssetTokenContract.balanceOf(securitizationPoolContract.address);
      expect(balanceOfPool).equal(tokenIds.length);

      await expect(
        loanKernel.fillDebtOrder(orderAddresses, orderValues, termsContractParameters, tokenIds)
      ).to.be.revertedWith(`ERC721: token already minted`);
    });
  });

  describe('#Securitization Pool', async () => {
    it('#exportAssets', async () => {
      await securitizationPoolContract
        .connect(poolCreatorSigner)
        .exportAssets(loanAssetTokenContract.address, secondSecuritizationPool.address, [tokenIds[1]]);

      const ownerOfAgreement = await loanAssetTokenContract.ownerOf(tokenIds[1]);
      expect(ownerOfAgreement).equal(secondSecuritizationPool.address);

      const balanceOfPool = await loanAssetTokenContract.balanceOf(secondSecuritizationPool.address);
      expect(balanceOfPool).equal(1);
    });

    it('#setPot', async () => {
      await securitizationPoolContract.connect(poolCreatorSigner).setPot(secondSecuritizationPool.address);
      expect(await securitizationPoolContract.pot()).equal(secondSecuritizationPool.address);

      // Set again
      await securitizationPoolContract.connect(poolCreatorSigner).setPot(securitizationPoolContract.address);
      expect(await securitizationPoolContract.pot()).equal(securitizationPoolContract.address);
    });

    it('#withdrawAssets', async () => {
      await secondSecuritizationPool
        .connect(poolCreatorSigner)
        .withdrawAssets([loanAssetTokenContract.address], [tokenIds[1]], [originatorSigner.address]);

      const ownerOfAgreement = await loanAssetTokenContract.ownerOf(tokenIds[1]);
      expect(ownerOfAgreement).equal(originatorSigner.address);

      const balanceOfPoolCreator = await loanAssetTokenContract.balanceOf(originatorSigner.address);
      expect(balanceOfPoolCreator).equal(1);
    });

    it('#collectAssets', async () => {
      await loanAssetTokenContract.connect(originatorSigner).setApprovalForAll(secondSecuritizationPool.address, true);

      await secondSecuritizationPool
        .connect(originatorSigner)
        .collectAssets(loanAssetTokenContract.address, originatorSigner.address, [tokenIds[1]]);

      const ownerOfAgreement = await loanAssetTokenContract.ownerOf(tokenIds[1]);
      expect(ownerOfAgreement).equal(secondSecuritizationPool.address);

      const balanceOfPoolCreator = await loanAssetTokenContract.balanceOf(secondSecuritizationPool.address);
      expect(balanceOfPoolCreator).equal(1);
    });

    it('#withdraw', async () => {
      await securitizationPoolContract.connect(originatorSigner).withdraw(parseEther('10'));
    });

    it('#collectERC20Assets', async () => {
      await sotToken.connect(lenderSigner).approve(securitizationPoolContract.address, unlimitedAllowance);

      await securitizationPoolContract
        .connect(originatorSigner)
        .collectERC20Assets([sotToken.address], [lenderSigner.address], [parseEther('2')]);

      expect(formatEther(await sotToken.balanceOf(lenderSigner.address))).equal('88.0');
    });

    it('#withdrawERC20Assets', async () => {
      await securitizationPoolContract
        .connect(poolCreatorSigner)
        .withdrawERC20Assets([sotToken.address], [lenderSigner.address], [parseEther('1')]);

      expect(formatEther(await sotToken.balanceOf(lenderSigner.address))).equal('89.0');
    });

    it('#claimERC20Assets', async () => {
      await securitizationPoolContract.connect(poolCreatorSigner).claimERC20Assets([sotToken.address]);

      expect(formatEther(await sotToken.balanceOf(lenderSigner.address))).equal('89.0');
    });

    it('#claimCashRemain', async () => {
      expect(formatEther(await stableCoin.balanceOf(poolCreatorSigner.address))).equal('0.0');
      await expect(
        securitizationPoolContract.connect(poolCreatorSigner).claimCashRemain(poolCreatorSigner.address)
      ).to.be.revertedWith(`SecuritizationPool: SOT still remain`);

      await stableCoin.mint(parseEther('100000000000000'));
      await stableCoin.connect(untangledAdminSigner).transfer(lenderSigner.address, parseEther('1000000'));
      await securitizationManager
        .connect(lenderSigner)
        .buyTokens(mintedIncreasingInterestTGE.address, parseEther('90000'));
      await securitizationPoolContract.connect(poolCreatorSigner).claimCashRemain(poolCreatorSigner.address);
    });

    it('#startCycle', async () => {
      expect(formatEther(await stableCoin.balanceOf(poolCreatorSigner.address))).equal('0.0');
      await expect(
        securitizationPoolContract
          .connect(poolCreatorSigner)
          .startCycle(86400, parseEther('10000'), 5000, dayjs(new Date()).add(8, 'days').unix())
      ).to.be.revertedWith(`SecuritizationPool: sale is still on going`);
      await time.increaseTo(dayjs(new Date()).add(8, 'days').unix());
      await mintedIncreasingInterestTGE.finalize(false, untangledAdminSigner.address);

      await securitizationPoolContract
        .connect(poolCreatorSigner)
        .startCycle(86400, parseEther('10000'), 5000, dayjs(new Date()).add(8, 'days').unix());
    });
  });

  describe('Burn agreement', async () => {
    it('only LoanKernel contract can burn', async () => {
      await loanRepaymentRouter
        .connect(untangledAdminSigner)
        .repayInBatch([tokenIds[0]], [parseEther('100')], stableCoin.address);

      await expect(loanAssetTokenContract.ownerOf(tokenIds[0])).to.be.revertedWith(`ERC721: invalid token ID`);
    });
  });
});
