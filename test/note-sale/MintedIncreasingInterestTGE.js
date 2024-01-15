const { expect, assert } = require('chai');
const { ethers, upgrades } = require('hardhat');
const { setup, initPool } = require('../setup');
const { time } = require('@nomicfoundation/hardhat-network-helpers');
const { BigNumber, utils } = require('ethers');
const { POOL_ADMIN_ROLE, ORIGINATOR_ROLE } = require('../constants');
const { getPoolByAddress, unlimitedAllowance } = require('../utils');
const dayjs = require('dayjs');
const { presignedMintMessage } = require('../shared/uid-helper');
const { SaleType } = require('../shared/constants');
const { snapshot } = require('@openzeppelin/test-helpers');
const { parseEther } = ethers.utils;

const ONE_DAY_IN_SECONDS = 86400;

describe('MintedIncreasingInterestTGE', function () {
  let MintedIncreasingInterestTGE;
  let mintedIncreasingInterestTGE;
  let untangledAdminSigner;
  // let owner; // Replace with your contract owner's address
  let securitizationManager; // Replace with the address of the securitization manager or pool
  let accounts;
  let registry;
  let securitizationPool;
  let openingTime;
  let closingTime;
  let rate;
  let cap;

  let initialInterest; // Your desired initial interest rate
  let finalInterest; // Your desired final interest rate
  let timeInterval; // 1 hour
  let amountChangeEachInterval; // Your desired amount change

  before(async function () {
    ({ registry, stableCoin, securitizationManager, noteTokenFactory } = await setup());

    MintedIncreasingInterestTGE = await ethers.getContractFactory('MintedIncreasingInterestTGE'); // Replace with your contract name
    // [owner, securitizationManager, ...accounts] = await ethers.getSigners();

    const NoteToken = await ethers.getContractFactory('NoteToken');

    mintedIncreasingInterestTGE = await MintedIncreasingInterestTGE.deploy(/* constructor arguments */); // Replace with constructor arguments if needed
    await mintedIncreasingInterestTGE.deployed();

    // securitizationPool = await SecuritizationPool.deploy();


    let originatorSigner, poolCreatorSigner, borrowerSigner;
    [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, ...accounts] =
      await ethers.getSigners();




    const OWNER_ROLE = await securitizationManager.OWNER_ROLE();
    await securitizationManager.grantRole(OWNER_ROLE, borrowerSigner.address);
    await securitizationManager.setRoleAdmin(POOL_ADMIN_ROLE, OWNER_ROLE);
    await securitizationManager.connect(borrowerSigner).grantRole(POOL_ADMIN_ROLE, poolCreatorSigner.address);

    const salt = utils.keccak256(Date.now());


    let transaction = await securitizationManager
      .connect(poolCreatorSigner)

      .newPoolInstance(
        salt,

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

    let receipt = await transaction.wait();
    let [securitizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;
    securitizationPool = await getPoolByAddress(securitizationPoolAddress);

    const currencyAddress = await securitizationPool.underlyingCurrency();
    const longSale = true;

    const noteToken = await NoteToken.deploy();

    await mintedIncreasingInterestTGE.initialize(
      registry.address,
      untangledAdminSigner.address,
      noteToken.address,
      currencyAddress,
      longSale
    );

  });

  it('Get isLongSale', async () => {
    expect(await mintedIncreasingInterestTGE.isLongSale()).to.equal(true);
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
      .connect(untangledAdminSigner)
      .setInterestRange(initialInterest, finalInterest, timeInterval, amountChangeEachInterval);

    // Verify that the interest rate range was set correctly
    const actualInitialInterest = await mintedIncreasingInterestTGE.initialInterest();
    const actualFinalInterest = await mintedIncreasingInterestTGE.finalInterest();
    const actualTimeInterval = await mintedIncreasingInterestTGE.timeInterval();
    const actualAmountChangeEachInterval = await mintedIncreasingInterestTGE.amountChangeEachInterval();

    expect(actualInitialInterest).to.equal(BigNumber.from(initialInterest));
    expect(actualFinalInterest).to.equal(BigNumber.from(finalInterest));
    expect(actualTimeInterval).to.equal(BigNumber.from(timeInterval));
    expect(actualAmountChangeEachInterval).to.equal(BigNumber.from(amountChangeEachInterval));
  });

  it('should allow the owner or pool to start a new round sale', async function () {
    openingTime = (await time.latest()) + 60; // Starts 1 minute from now
    closingTime = openingTime + ONE_DAY_IN_SECONDS; // Ends 1 hour after opening
    rate = 100; // Your desired rate
    cap = ethers.utils.parseEther('1000'); // Your desired cap in ether

    // Only the owner (or pool) should be able to start a new round sale
    await expect(
      mintedIncreasingInterestTGE.connect(accounts[0]).startNewRoundSale(openingTime, closingTime, rate, cap)
    ).to.be.revertedWith('MintedIncreasingInterestTGE: Caller must be owner or manager');

    // The owner (or pool) should be able to start a new round sale
    await mintedIncreasingInterestTGE.connect(untangledAdminSigner).startNewRoundSale(openingTime, closingTime, rate, cap);

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
    await expect(mintedIncreasingInterestTGE.finalize(false, await securitizationPool.pot())).to.be.revertedWith(
      'FinalizableCrowdsale: not closed'
    );
    await time.increaseTo(closingTime + ONE_DAY_IN_SECONDS);
    await mintedIncreasingInterestTGE.finalize(false, await securitizationPool.pot());
    const pickedInterest = await mintedIncreasingInterestTGE.pickedInterest();
    expect(pickedInterest).to.equal(BigNumber.from(finalInterest));
  });
});
describe('Increasing Interest TGE', () => {
  let stableCoin;
  let registry;
  let loanAssetTokenContract;
  let loanRegistry;
  let loanKernel;
  let loanRepaymentRouter;
  let securitizationManager;
  let securitizationPoolContract;
  let tokenIds;
  let defaultLoanAssetTokenValidator;
  let uniqueIdentity;
  let sotToken;
  let jotToken;
  let contracts;
  let mintedIncreasingInterestTGE;
  let jotMintedNormalTGE;
  let securitizationPoolValueService;
  let securitizationPoolImpl;
  let distributionAssessor;
  let chainId;
  const INITIAL_INTEREST = 10000;
  // Wallets
  let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer;
  before('create fixture', async () => {
    [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer] =
        await ethers.getSigners();

    contracts = await setup();
    ({
      stableCoin,
      registry,
      loanAssetTokenContract,
      loanRegistry,
      loanKernel,
      loanRepaymentRouter,
      securitizationManager,
      securitizationPoolValueService,
      securitizationPoolImpl,
      defaultLoanAssetTokenValidator,
      uniqueIdentity,
      distributionAssessor,
    } = contracts);


    await stableCoin.mint(parseEther('1000000'));
    await stableCoin.transfer(lenderSigner.address, parseEther('1000000'));

    await stableCoin.connect(untangledAdminSigner).approve(loanRepaymentRouter.address, unlimitedAllowance);

    // Gain UID
    const UID_TYPE = 0;
    chainId = await getChainId();
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

  describe('#Preparation', async () => {
    it('Create pool', async () => {
      await securitizationManager.grantRole(POOL_ADMIN_ROLE, poolCreatorSigner.address);
      // Create new pool
      const transaction = await securitizationManager.connect(poolCreatorSigner).newPoolInstance(
          utils.keccak256(Date.now()),

          poolCreatorSigner.address,
          utils.defaultAbiCoder.encode(
              [
                {
                  type: 'tuple',
                  components: [
                    {
                      name: 'currency',
                      type: 'address',
                    },
                    {
                      name: 'minFirstLossCushion',
                      type: 'uint32',
                    },
                    {
                      name: 'validatorRequired',
                      type: 'bool',
                    },
                    {
                      name: 'debtCeiling',
                      type: 'uint256',
                    },
                  ],
                },
              ],
              [
                {
                  currency: stableCoin.address,
                  minFirstLossCushion: '100000',
                  validatorRequired: true,
                  debtCeiling: parseEther('100000').toString(),
                },
              ]
          )
      );

      const receipt = await transaction.wait();
      const [securitizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;

      securitizationPoolContract = await getPoolByAddress(securitizationPoolAddress);
      await securitizationPoolContract
          .connect(poolCreatorSigner)
          .grantRole(ORIGINATOR_ROLE, untangledAdminSigner.address);

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
    it('Set up TGE for JOT', async () => {
      const openingTime = dayjs(new Date()).unix();
      const closingTime = dayjs(new Date()).add(7, 'days').unix();
      const rate = 2;
      const totalCapOfToken = parseEther('100000');
      const prefixOfNoteTokenSaleName = 'JOT_';
      const initialJotAmount = parseEther('100');

      // JOT only has SaleType.NORMAL_SALE
      const transaction = await securitizationManager.connect(poolCreatorSigner).setUpTGEForJOT(
          {
            issuerTokenController: untangledAdminSigner.address,
            pool: securitizationPoolContract.address,
            minBidAmount: parseEther('1'),
            saleType: SaleType.NORMAL_SALE,
            longSale: true,
            ticker: prefixOfNoteTokenSaleName,
          },
          { openingTime: openingTime, closingTime: closingTime, rate: rate, cap: totalCapOfToken },
          initialJotAmount
      );
      const receipt = await transaction.wait();

      const [tgeAddress] = receipt.events.find((e) => e.event == 'NewTGECreated').args;

      expect(tgeAddress).to.be.properAddress;

      jotMintedNormalTGE = await ethers.getContractAt('MintedNormalTGE', tgeAddress);

      const [jotTokenAddress] = receipt.events.find((e) => e.event == 'NewNotesTokenCreated').args;
      expect(jotTokenAddress).to.be.properAddress;

      jotToken = await ethers.getContractAt('NoteToken', jotTokenAddress);
    });

  });

  describe('Increasing interest TGE stopped TGE end time', async () => {
    let snap;
    before(async () => {
      snap = await snapshot();
    });
    describe('#getCurrentInterest', () => {
      before('Set up TGE for SOT', async () => {
        const openingTime = dayjs(new Date()).unix();
        const closingTime = dayjs(new Date()).add(7, 'days').unix();
        const rate = 2;
        const totalCapOfToken = parseEther('100000');
        const finalInterest = 40000;
        const timeInterval = 1 * 24 * 3600; // one day in seconds
        const amountChangeEachInterval = 5000; // 0.5%
        const prefixOfNoteTokenSaleName = 'SOT_';

        const transaction = await securitizationManager.connect(poolCreatorSigner).setUpTGEForSOT(
            {
              issuerTokenController: untangledAdminSigner.address,
              pool: securitizationPoolContract.address,
              minBidAmount: parseEther('1'),
              saleType: SaleType.MINTED_INCREASING_INTEREST,
              longSale: true,
              ticker: prefixOfNoteTokenSaleName,
            },
            { openingTime: openingTime, closingTime: closingTime, rate: rate, cap: totalCapOfToken },
            {
              initialInterest: INITIAL_INTEREST,
              finalInterest,
              timeInterval,
              amountChangeEachInterval,
            }
        );

        const receipt = await transaction.wait();

        const [tgeAddress] = receipt.events.find((e) => e.event == 'NewTGECreated').args;
        expect(tgeAddress).to.be.properAddress;

        mintedIncreasingInterestTGE = await ethers.getContractAt('MintedIncreasingInterestTGE', tgeAddress);

        const [sotTokenAddress] = receipt.events.find((e) => e.event == 'NewNotesTokenCreated').args;
        expect(sotTokenAddress).to.be.properAddress;

        sotToken = await ethers.getContractAt('NoteToken', sotTokenAddress);
      });
      it('should return initial interest', async () => {
        const currentInterest = await mintedIncreasingInterestTGE.getCurrentInterest();
        expect(currentInterest).equal(INITIAL_INTEREST);
      });
      it('should return increasing interest correctly after 2 days', async () => {
          await time.increase(2 * 86400); // 2 days
          const currentInterest = await mintedIncreasingInterestTGE.getCurrentInterest();
          expect(currentInterest).equal(20000);//2%
      });
      it('should return increasing interest correctly after next 1 day', async () => {
        await time.increase(1 * 86400); // 2 days
        const currentInterest = await mintedIncreasingInterestTGE.getCurrentInterest();
        expect(currentInterest).equal(25000);//2.5%
      });
      it('should return increasing interest correctly after next 4 days (7 days from openTime)', async () => {
        await time.increase(5 * 86400); // 2 days
        const currentInterest = await mintedIncreasingInterestTGE.getCurrentInterest();
        expect(currentInterest).equal(40000);//4% (maximum = final interest)
      });
    });
    describe('#startCycle', () => {
      it('should start cycle successfully', async () => {
        await securitizationPoolContract.connect(lenderSigner).startCycle();
        expect(await securitizationPoolContract.state()).to.equal(2); // Check pool state
        expect(await jotMintedNormalTGE.finalized()).to.equal(true); // Check TGE state
        expect(await mintedIncreasingInterestTGE.finalized()).to.equal(true); // Check TGE state
        expect(await mintedIncreasingInterestTGE.pickedInterest()).to.equal(40000)
        expect(await securitizationPoolContract.interestRateSOT()).to.equal(40000)
      });
      it('should not start cycle again', async () => {
        await expect(securitizationPoolContract.connect(lenderSigner).startCycle()).to.be.revertedWith(
            'Not in issuing token stage'
        );
      });
    });
    after(async () => {
      await snap.restore();
    })

  });

  describe('Increasing interest TGE stopped by reaching TGE max cap', async () => {
    describe('#getCurrentInterest', () => {
      before('Set up TGE for SOT', async () => {
        const openingTime = dayjs(new Date()).unix();
        const closingTime = dayjs(new Date()).add(7, 'days').unix();
        const rate = 2;
        const totalCapOfToken = parseEther('20000');
        const finalInterest = 40000;
        const timeInterval = 1 * 24 * 3600; // one day in seconds
        const amountChangeEachInterval = 5000; // 0.5%
        const prefixOfNoteTokenSaleName = 'SOT_';

        const transaction = await securitizationManager.connect(poolCreatorSigner).setUpTGEForSOT(
            {
              issuerTokenController: untangledAdminSigner.address,
              pool: securitizationPoolContract.address,
              minBidAmount: parseEther('1'),
              saleType: SaleType.MINTED_INCREASING_INTEREST,
              longSale: true,
              ticker: prefixOfNoteTokenSaleName,
            },
            { openingTime: openingTime, closingTime: closingTime, rate: rate, cap: totalCapOfToken },
            {
              initialInterest: INITIAL_INTEREST,
              finalInterest,
              timeInterval,
              amountChangeEachInterval,
            }
        );

        const receipt = await transaction.wait();

        const [tgeAddress] = receipt.events.find((e) => e.event == 'NewTGECreated').args;
        expect(tgeAddress).to.be.properAddress;

        mintedIncreasingInterestTGE = await ethers.getContractAt('MintedIncreasingInterestTGE', tgeAddress);

        const [sotTokenAddress] = receipt.events.find((e) => e.event == 'NewNotesTokenCreated').args;
        expect(sotTokenAddress).to.be.properAddress;

        sotToken = await ethers.getContractAt('NoteToken', sotTokenAddress);
      });
      it('should return initial interest', async () => {
        const currentInterest = await mintedIncreasingInterestTGE.getCurrentInterest();
        expect(currentInterest).equal(INITIAL_INTEREST);
      });
      it('should return increasing interest correctly after 2 days', async () => {
        await time.increase(2 * 86400); // 2 days
        const currentInterest = await mintedIncreasingInterestTGE.getCurrentInterest();
        expect(currentInterest).equal(20000);//2%
      });
      it('Buy tokens', async () => {
          await stableCoin.connect(lenderSigner).approve(mintedIncreasingInterestTGE.address, unlimitedAllowance);

          await stableCoin.connect(lenderSigner).approve(jotMintedNormalTGE.address, unlimitedAllowance);
          await securitizationManager
              .connect(lenderSigner)
              .buyTokens(jotMintedNormalTGE.address, parseEther('10000'));

          await securitizationManager
              .connect(lenderSigner)
              .buyTokens(mintedIncreasingInterestTGE.address, parseEther('10000'));
      });
      it('Buy more SOT to reach TGE max cap', async () => {
        await securitizationManager
            .connect(lenderSigner)
            .buyTokens(mintedIncreasingInterestTGE.address, parseEther('10000'));
      })

      it('should return increasing interest correctly & keep picked interest unchanged after next 1 day (3 days from openTime)', async () => {
        await time.increase(1 * 86400); // 1 day
        const currentInterest = await mintedIncreasingInterestTGE.getCurrentInterest();
        expect(currentInterest).equal(25000);//2.5%
        expect(await mintedIncreasingInterestTGE.pickedInterest()).to.equal(20000);
      });
      it('should return increasing interest correctly & keep picked interest unchanged after next 4 days (7 days from openTime)', async () => {
        await time.increase(5 * 86400); // 2 days
        const currentInterest = await mintedIncreasingInterestTGE.getCurrentInterest();
        expect(currentInterest).equal(40000);//4% (maximum = final interest)
        expect(await mintedIncreasingInterestTGE.pickedInterest()).to.equal(20000);
      });
    });
    describe('#startCycle', () => {
      it('should start cycle successfully', async () => {
        await securitizationPoolContract.connect(lenderSigner).startCycle();
        expect(await securitizationPoolContract.state()).to.equal(2); // Check pool state
        expect(await jotMintedNormalTGE.finalized()).to.equal(true); // Check TGE state
        expect(await mintedIncreasingInterestTGE.finalized()).to.equal(true); // Check TGE state
        expect(await mintedIncreasingInterestTGE.pickedInterest()).to.equal(20000)
        expect(await securitizationPoolContract.interestRateSOT()).to.equal(20000)
      });
      it('should not start cycle again', async () => {
        await expect(securitizationPoolContract.connect(lenderSigner).startCycle()).to.be.revertedWith(
            'Not in issuing token stage'
        );
      });
    });

  });

});
