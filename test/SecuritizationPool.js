const { ethers } = require('hardhat');
const _ = require('lodash');
const dayjs = require('dayjs');
const { expect } = require('chai');
const { time } = require('@nomicfoundation/hardhat-network-helpers');

const { constants } = ethers;
const { parseEther, formatEther } = ethers.utils;
const { presignedMintMessage } = require('./shared/uid-helper.js');

const {
  unlimitedAllowance,
  genLoanAgreementIds,
  saltFromOrderValues,
  debtorsFromOrderAddresses,
  packTermsContractParameters,
  interestRateFixedPoint,
  genSalt,
} = require('./utils.js');
const { setup } = require('./setup.js');
const { SaleType } = require('./shared/constants.js');

const { POOL_ADMIN_ROLE } = require('./constants.js');

const RATE_SCALING_FACTOR = 10 ** 4;

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
  let jotToken;
  let distributionTranche;
  let mintedIncreasingInterestTGE;
  let jotMintedIncreasingInterestTGE;
  let securitizationPoolValueService;
  let factoryAdmin;
  let securitizationPoolImpl;

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
      securitizationPoolValueService,
      factoryAdmin,
      securitizationPoolImpl,
    } = await setup());

    await stableCoin.transfer(lenderSigner.address, parseEther('1000'));

    await stableCoin.connect(untangledAdminSigner).approve(loanRepaymentRouter.address, unlimitedAllowance);

    // Gain UID
    const UID_TYPE = 0;
    const chainId = await getChainId();
    const expiredAt = dayjs().unix() + 86400 * 1000;
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

      const OWNER_ROLE = await securitizationManager.OWNER_ROLE();
      await securitizationManager.setRoleAdmin(POOL_ADMIN_ROLE, OWNER_ROLE);

      await securitizationManager.grantRole(OWNER_ROLE, borrowerSigner.address);
      await securitizationManager.connect(borrowerSigner).grantRole(POOL_ADMIN_ROLE, poolCreatorSigner.address);

      // Create new pool
      let transaction = await securitizationManager
        .connect(poolCreatorSigner)
        .newPoolInstance(stableCoin.address, '100000', poolCreatorSigner.address);
      let receipt = await transaction.wait();
      let [securitizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;

      securitizationPoolContract = await ethers.getContractAt('SecuritizationPool', securitizationPoolAddress);
      await securitizationPoolContract
        .connect(poolCreatorSigner)
        .grantRole(await securitizationPoolContract.ORIGINATOR_ROLE(), originatorSigner.address);

      transaction = await securitizationManager
        .connect(poolCreatorSigner)
        .newPoolInstance(stableCoin.address, '100000', poolCreatorSigner.address);
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
        discountRate: 100000,
      };
      const daysPastDues = [riskScore.daysPastDue];
      const ratesAndDefaults = [
        riskScore.advanceRate,
        riskScore.penaltyRate,
        riskScore.interestRate,
        riskScore.probabilityOfDefault,
        riskScore.lossGivenDefault,
        riskScore.discountRate,
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

    it('Wrong risk scores', async () => {
      const oneDayInSecs = 1 * 24 * 3600;
      const halfOfADay = oneDayInSecs / 2;

      const riskScore = {
        daysPastDue: oneDayInSecs,
        advanceRate: 950000,
        penaltyRate: 900000,
        interestRate: 910000,
        probabilityOfDefault: 800000,
        lossGivenDefault: 810000,
        discountRate: 100000,
        gracePeriod: halfOfADay,
        collectionPeriod: halfOfADay,
        writeOffAfterGracePeriod: halfOfADay,
        writeOffAfterCollectionPeriod: halfOfADay,
      };
      const daysPastDues = [riskScore.daysPastDue, riskScore.daysPastDue];
      const ratesAndDefaults = [
        riskScore.advanceRate,
        riskScore.penaltyRate,
        riskScore.interestRate,
        riskScore.probabilityOfDefault,
        riskScore.lossGivenDefault,
        riskScore.discountRate,
        riskScore.advanceRate,
        riskScore.penaltyRate,
        riskScore.interestRate,
        riskScore.probabilityOfDefault,
        riskScore.lossGivenDefault,
        riskScore.discountRate,
      ];
      const periodsAndWriteOffs = [
        riskScore.gracePeriod,
        riskScore.collectionPeriod,
        riskScore.writeOffAfterGracePeriod,
        riskScore.writeOffAfterCollectionPeriod,
        riskScore.gracePeriod,
        riskScore.collectionPeriod,
        riskScore.writeOffAfterGracePeriod,
        riskScore.writeOffAfterCollectionPeriod,
      ];

      await expect(
        securitizationPoolContract
          .connect(poolCreatorSigner)
          .setupRiskScores(daysPastDues, ratesAndDefaults, periodsAndWriteOffs)
      ).to.be.revertedWith(`SecuritizationPool: Risk scores must be sorted`);
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

    it('Should set up TGE for JOT successfully', async () => {
      const tokenDecimals = 18;

      const openingTime = dayjs(new Date()).unix();
      const closingTime = dayjs(new Date()).add(7, 'days').unix();
      const rate = 2;
      const totalCapOfToken = parseEther('100000');
      const initialJOTAmount = parseEther('1');
      const prefixOfNoteTokenSaleName = 'JOT_';

      // JOT only has SaleType.NORMAL_SALE
      const transaction = await securitizationManager
        .connect(poolCreatorSigner)
        .setUpTGEForJOT(
          untangledAdminSigner.address,
          securitizationPoolContract.address,
          initialJOTAmount,
          [SaleType.NORMAL_SALE, tokenDecimals],
          true,
          { openingTime: openingTime, closingTime: closingTime, rate: rate, cap: totalCapOfToken },
          prefixOfNoteTokenSaleName
        );
      const receipt = await transaction.wait();

      const [tgeAddress] = receipt.events.find((e) => e.event == 'NewTGECreated').args;
      expect(tgeAddress).to.be.properAddress;

      jotMintedIncreasingInterestTGE = await ethers.getContractAt('MintedIncreasingInterestTGE', tgeAddress);

      const [jotTokenAddress] = receipt.events.find((e) => e.event == 'NewNotesTokenCreated').args;
      expect(jotTokenAddress).to.be.properAddress;

      jotToken = await ethers.getContractAt('NoteToken', jotTokenAddress);
    });

    it('Should buy tokens failed if buy sot first', async () => {
      await stableCoin.connect(lenderSigner).approve(mintedIncreasingInterestTGE.address, unlimitedAllowance);

      await expect(
        securitizationManager.connect(lenderSigner).buyTokens(mintedIncreasingInterestTGE.address, parseEther('100'))
      ).to.be.revertedWith(`Crowdsale: sale not started`);
    });

    it('Should buy tokens successfully', async () => {
      await stableCoin.connect(lenderSigner).approve(jotMintedIncreasingInterestTGE.address, unlimitedAllowance);
      await securitizationManager
        .connect(lenderSigner)
        .buyTokens(jotMintedIncreasingInterestTGE.address, parseEther('100'));

      await securitizationManager
        .connect(lenderSigner)
        .buyTokens(mintedIncreasingInterestTGE.address, parseEther('100'));

      const stablecoinBalanceOfPayerAfter = await stableCoin.balanceOf(lenderSigner.address);
      expect(formatEther(stablecoinBalanceOfPayerAfter)).equal('800.0');

      expect(formatEther(await stableCoin.balanceOf(securitizationPoolContract.address))).equal('200.0');
    });
  });

  describe('#Pool value service', async () => {
    it('#getOutstandingPrincipalCurrencyByInvestor', async () => {
      const result = await securitizationPoolValueService.getOutstandingPrincipalCurrencyByInvestor(
        securitizationPoolContract.address,
        lenderSigner.address
      );

      expect(formatEther(result)).equal('100.0');
    });

    it('#getExpectedAssetsValue', async () => {
      const result = await securitizationPoolValueService.getExpectedAssetsValue(
        securitizationPoolContract.address,
        dayjs(new Date()).add(1, 'days').unix()
      );

      expect(formatEther(result)).equal('0.0');
    });

    it('#getSeniorAsset', async () => {
      const result = await securitizationPoolValueService.getSeniorAsset(securitizationPoolContract.address);

      expect(formatEther(result)).equal('100.0');
    });

    it('#getJuniorAsset', async () => {
      const result = await securitizationPoolValueService.getJuniorAsset(securitizationPoolContract.address);

      expect(formatEther(result)).equal('100.0');
    });

    it('#getJuniorRatio', async () => {
      const result = await securitizationPoolValueService.getJuniorRatio(securitizationPoolContract.address);

      expect(result.toNumber() / RATE_SCALING_FACTOR).equal(50);
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
  const ASSET_PURPOSE_SALE = '0';
  const ASSET_PURPOSE_PLEDGE = '1';
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
        ASSET_PURPOSE_SALE,
        parseEther(principalAmount.toString()), // token 1
        parseEther(principalAmount.toString()), // token 2
        expirationTimestamps,
        expirationTimestamps,
        genSalt(),
        genSalt(),
        riskScore,
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

      await loanKernel.fillDebtOrder(orderAddresses, orderValues, termsContractParameters,
        tokenIds.map(x => ({
          tokenId: x,
          nonce: 0,
          validator: constants.AddressZero,
          validateSignature: Buffer.from([])
        }))
      );

      const ownerOfAgreement = await loanAssetTokenContract.ownerOf(tokenIds[0]);
      expect(ownerOfAgreement).equal(securitizationPoolContract.address);

      const balanceOfPool = await loanAssetTokenContract.balanceOf(securitizationPoolContract.address);
      expect(balanceOfPool).equal(tokenIds.length);

      await expect(
        loanKernel.fillDebtOrder(orderAddresses, orderValues, termsContractParameters,
          tokenIds.map(x => ({
            tokenId: x,
            nonce: 0,
            validator: constants.AddressZero,
            validateSignature: Buffer.from([])
          }))
        )
      ).to.be.revertedWith(`ERC721: token already minted`);
    });

    it('Execute fillDebtOrder successfully with Pledge', async () => {
      const orderAddresses = [
        securitizationPoolContract.address,
        stableCoin.address,
        loanRepaymentRouter.address,
        loanInterestTermsContract.address,
        relayer.address,
        // borrower 1
        borrowerSigner.address,
      ];

      const riskScore = '50';
      expirationTimestamps = dayjs(new Date()).add(7, 'days').unix();

      const orderValues = [
        CREDITOR_FEE,
        ASSET_PURPOSE_PLEDGE,
        // token 1
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

      const termsContractParameters = [termsContractParameter];

      const salts = saltFromOrderValues(orderValues, termsContractParameters.length);
      const debtors = debtorsFromOrderAddresses(orderAddresses, termsContractParameters.length);

      const pledgeTokenIds = genLoanAgreementIds(
        loanRepaymentRouter.address,
        debtors,
        loanInterestTermsContract.address,
        termsContractParameters,
        salts
      );

      await loanKernel.fillDebtOrder(orderAddresses, orderValues, termsContractParameters,
        pledgeTokenIds.map(x => ({
          tokenId: x,
          nonce: 0,
          validator: constants.AddressZero,
          validateSignature: Buffer.from([])
        }))
      );

      const ownerOfAgreement = await loanAssetTokenContract.ownerOf(pledgeTokenIds[0]);
      expect(ownerOfAgreement).equal(securitizationPoolContract.address);

      tokenIds.push(...pledgeTokenIds);
      const balanceOfPool = await loanAssetTokenContract.balanceOf(securitizationPoolContract.address);
      expect(balanceOfPool).equal(tokenIds.length);
    });
  });

  describe('Pool value after loan kernel executed', async () => {
    it('#getExpectedAssetValues', async () => {
      const result = await securitizationPoolValueService.getExpectedAssetValues(
        securitizationPoolContract.address,
        [loanAssetTokenContract.address],
        [tokenIds[0]],
        dayjs(new Date()).add(1, 'days').unix()
      );

      expect(result.toString()).equal('14803');
    });

    it('#getAssetInterestRate', async () => {
      const result = await securitizationPoolValueService.getAssetInterestRate(
        securitizationPoolContract.address,
        loanAssetTokenContract.address,
        tokenIds[0],
        dayjs(new Date()).add(1, 'days').unix()
      );
      expect(result.toNumber()).equal(50000);
    });

    it('#getAssetInterestRates', async () => {
      const result = await securitizationPoolValueService.getAssetInterestRates(
        securitizationPoolContract.address,
        [loanAssetTokenContract.address],
        [tokenIds[0]],
        dayjs(new Date()).add(1, 'days').unix()
      );
      expect(result.map((x) => x.toNumber())).to.deep.equal([50000]);
    });

    it('#getExpectedERC20AssetValue', async () => {
      const result = await securitizationPoolValueService.getExpectedERC20AssetValue(
        securitizationPoolContract.address,
        securitizationPoolContract.address,
        sotToken.address,
        10000,
        dayjs(new Date()).add(1, 'days').unix()
      );
      expect(formatEther(result)).equal('0.0');
    });

    it('#getExpectedAssetsValue', async () => {
      const result = await securitizationPoolValueService.getExpectedAssetsValue(
        securitizationPoolContract.address,
        dayjs(new Date()).add(1, 'days').unix()
      );
      expect(result.toString()).equal('43902');
    });

    it('#getAssetRiskScoreIdx', async () => {
      const result = await securitizationPoolValueService.getAssetRiskScoreIdx(
        securitizationPoolContract.address,
        dayjs(new Date()).add(10, 'days').unix()
      );
      expect(result.hasValidRiskScore).equal(true);
      expect(result.riskScoreIdx.toNumber()).equal(0);
    });

    it('#getOutstandingPrincipalCurrencyByInvestors', async () => {
      const result = await securitizationPoolValueService.getOutstandingPrincipalCurrencyByInvestors(
        securitizationPoolContract.address,
        [lenderSigner.address]
      );
      expect(formatEther(result)).equal('90.0');
    });

    it('#getReserve', async () => {
      const result = await securitizationPoolValueService.getReserve(
        securitizationPoolContract.address,
        parseEther('15000'),
        parseEther('1000'),
        parseEther('1000')
      );
      expect(formatEther(result)).equal('15190.0');
    });

    it('#getOutstandingPrincipalCurrency', async () => {
      const result = await securitizationPoolValueService.getOutstandingPrincipalCurrency(
        securitizationPoolContract.address
      );
      expect(formatEther(result)).equal('90.0');
    });
  });

  describe('Upgradeables', async () => {
    it('Should upgrade to new Implementation successfully', async () => {
      const SecuritizationPoolV2 = await ethers.getContractFactory('SecuritizationPoolV2');
      const spV2Impl = await SecuritizationPoolV2.deploy();

      const spImpl = await factoryAdmin.getProxyImplementation(securitizationPoolContract.address);

      expect(securitizationPoolImpl.address).to.be.eq(spImpl);

      // Update new logic
      await factoryAdmin.connect(untangledAdminSigner).upgrade(securitizationPoolContract.address, spV2Impl.address);

      const newSpImpl = await factoryAdmin.getProxyImplementation(securitizationPoolContract.address);

      expect(spV2Impl.address).to.be.eq(newSpImpl);

      securitizationPoolContract = await ethers.getContractAt(
        'SecuritizationPoolV2',
        securitizationPoolContract.address
      );

      const result = await securitizationPoolContract.hello();

      expect(result).to.be.eq('Hello world');
    });
  });

  describe('Get Info after Upgrade', async () => {
    it('#getExpectedAssetValues', async () => {
      const result = await securitizationPoolValueService.getExpectedAssetValues(
        securitizationPoolContract.address,
        [loanAssetTokenContract.address],
        [tokenIds[0]],
        dayjs(new Date()).add(1, 'days').unix()
      );

      expect(result.toString()).equal('14803');
    });

    it('#getAssetInterestRate', async () => {
      const result = await securitizationPoolValueService.getAssetInterestRate(
        securitizationPoolContract.address,
        loanAssetTokenContract.address,
        tokenIds[0],
        dayjs(new Date()).add(1, 'days').unix()
      );
      expect(result.toNumber()).equal(50000);
    });

    it('#getAssetInterestRates', async () => {
      const result = await securitizationPoolValueService.getAssetInterestRates(
        securitizationPoolContract.address,
        [loanAssetTokenContract.address],
        [tokenIds[0]],
        dayjs(new Date()).add(1, 'days').unix()
      );
      expect(result.map((x) => x.toNumber())).to.deep.equal([50000]);
    });

    it('#getExpectedERC20AssetValue', async () => {
      const result = await securitizationPoolValueService.getExpectedERC20AssetValue(
        securitizationPoolContract.address,
        securitizationPoolContract.address,
        sotToken.address,
        10000,
        dayjs(new Date()).add(1, 'days').unix()
      );
      expect(formatEther(result)).equal('0.0');
    });

    it('#getExpectedAssetsValue', async () => {
      const result = await securitizationPoolValueService.getExpectedAssetsValue(
        securitizationPoolContract.address,
        dayjs(new Date()).add(1, 'days').unix()
      );
      expect(result.toString()).equal('43902');
    });

    it('#getAssetRiskScoreIdx', async () => {
      const result = await securitizationPoolValueService.getAssetRiskScoreIdx(
        securitizationPoolContract.address,
        dayjs(new Date()).add(10, 'days').unix()
      );
      expect(result.hasValidRiskScore).equal(true);
      expect(result.riskScoreIdx.toNumber()).equal(0);
    });

    it('#getOutstandingPrincipalCurrencyByInvestors', async () => {
      const result = await securitizationPoolValueService.getOutstandingPrincipalCurrencyByInvestors(
        securitizationPoolContract.address,
        [lenderSigner.address]
      );
      expect(formatEther(result)).equal('90.0');
    });

    it('#getReserve', async () => {
      const result = await securitizationPoolValueService.getReserve(
        securitizationPoolContract.address,
        parseEther('15000'),
        parseEther('1000'),
        parseEther('1000')
      );
      expect(formatEther(result)).equal('15190.0');
    });

    it('#getOutstandingPrincipalCurrency', async () => {
      const result = await securitizationPoolValueService.getOutstandingPrincipalCurrency(
        securitizationPoolContract.address
      );
      expect(formatEther(result)).equal('90.0');
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

      await expect(
        securitizationPoolContract
          .connect(poolCreatorSigner)
          .exportAssets(stableCoin.address, secondSecuritizationPool.address, [tokenIds[1]])
      ).to.be.revertedWith(`SecuritizationPool: Asset does not exist`);
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

    it('#getAssetInterestRate of Pledge token', async () => {
      const result = await securitizationPoolValueService.getAssetInterestRate(
        securitizationPoolContract.address,
        loanAssetTokenContract.address,
        tokenIds[2],
        dayjs(new Date()).add(1, 'days').unix()
      );
      expect(result.toNumber()).equal(910000);
    });

    it('#withdrawERC20Assets', async () => {
      await securitizationPoolContract
        .connect(poolCreatorSigner)
        .withdrawERC20Assets([sotToken.address], [lenderSigner.address], [parseEther('1')]);

      expect(formatEther(await sotToken.balanceOf(lenderSigner.address))).equal('89.0');
    });

    it('#claimCashRemain', async () => {
      expect(formatEther(await stableCoin.balanceOf(poolCreatorSigner.address))).equal('0.0');
      expect(formatEther(await sotToken.totalSupply())).equal('90.0');
      await expect(
        securitizationPoolContract.connect(poolCreatorSigner).claimCashRemain(poolCreatorSigner.address)
      ).to.be.revertedWith(`SecuritizationPool: SOT still remain`);

      await securitizationPoolContract
        .connect(poolCreatorSigner)
        .withdrawERC20Assets([sotToken.address], [lenderSigner.address], [parseEther('1')]);

      // Force burn to test
      await sotToken.connect(lenderSigner).burn(parseEther('90'));
      expect(formatEther(await sotToken.totalSupply())).equal('0.0');

      await expect(
        securitizationPoolContract.connect(poolCreatorSigner).claimCashRemain(poolCreatorSigner.address)
      ).to.be.revertedWith(`SecuritizationPool: JOT still remain`);

      // Force burn to test
      await jotToken.connect(lenderSigner).burn(parseEther('100'));
      expect(formatEther(await jotToken.totalSupply())).equal('0.0');

      await securitizationPoolContract.connect(poolCreatorSigner).claimCashRemain(poolCreatorSigner.address);
    });

    it('#startCycle', async () => {
      expect(formatEther(await stableCoin.balanceOf(poolCreatorSigner.address))).equal('180.0');
      await expect(
        securitizationPoolContract
          .connect(poolCreatorSigner)
          .startCycle(86400, parseEther('10000'), 5000, dayjs(new Date()).add(8, 'days').unix())
      ).to.be.revertedWith(`FinalizableCrowdsale: not closed`);

      await time.increaseTo(dayjs(new Date()).add(8, 'days').unix());

      await expect(mintedIncreasingInterestTGE.finalize(false, untangledAdminSigner.address)).to.be.revertedWith(
        `FinalizableCrowdsale: Only pool contract can finalize`
      );

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

  describe('Get Info', async () => {
    it('#getTokenAssetAddresses', async () => {
      const tokens = await securitizationPoolContract.getTokenAssetAddresses();

      expect(tokens).to.deep.equal([sotToken.address]);
    });
  });
});
