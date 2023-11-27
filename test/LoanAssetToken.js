const { ethers, upgrades } = require('hardhat');
const { snapshot } = require('@openzeppelin/test-helpers');
const _ = require('lodash');
const dayjs = require('dayjs');
const { expect } = require('chai');

const { BigNumber, constants } = ethers;
const { parseEther, formatEther } = ethers.utils;

const {
  unlimitedAllowance,
  genLoanAgreementIds,
  saltFromOrderValues,
  debtorsFromOrderAddresses,
  packTermsContractParameters,
  interestRateFixedPoint,
  genSalt,
  generateLATMintPayload,
} = require('./utils.js');
const { setup } = require('./setup.js');

const { POOL_ADMIN_ROLE } = require('./constants.js');
const { utils } = require('ethers');

describe('LoanAssetToken', () => {
  let stableCoin;
  let registry;
  let loanAssetTokenContract;
  let loanInterestTermsContract;
  let loanRegistry;
  let loanKernel;
  let loanRepaymentRouter;
  let securitizationManager;
  let securitizationPoolContract;
  let tokenIds;
  let defaultLoanAssetTokenValidator;

  // Wallets
  let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer;
  before('create fixture', async () => {
    [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer] =
      await ethers.getSigners();

    ({
      stableCoin,
      registry,
      loanAssetTokenContract,
      loanInterestTermsContract,
      loanRegistry,
      loanKernel,
      loanRepaymentRouter,
      securitizationManager,
      securitizationPoolValueService,
      securitizationPoolImpl,
      defaultLoanAssetTokenValidator,
    } = await setup());

    await stableCoin.transfer(lenderSigner.address, parseEther('1000'));

    await stableCoin.connect(untangledAdminSigner).approve(loanRepaymentRouter.address, unlimitedAllowance);
  });

  describe('#security pool', async () => {
    it('Create pool', async () => {

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
                  name: "validatorRequired",
                  type: "bool"
                }
              ]
            }
          ], [
            {
              currency: stableCoin.address,
              minFirstLossCushion: '100000',
              validatorRequired: true
            }
          ]));
          

      const receipt = await transaction.wait();
      const [securitizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;

      securitizationPoolContract = await ethers.getContractAt('SecuritizationPool', securitizationPoolAddress);

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
        discountRate: 100000
      };
      const daysPastDues = [riskScore.daysPastDue];
      const ratesAndDefaults = [
        riskScore.advanceRate,
        riskScore.penaltyRate,
        riskScore.interestRate,
        riskScore.probabilityOfDefault,
        riskScore.lossGivenDefault,
        riskScore.discountRate
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

  let expirationTimestamps;
  const CREDITOR_FEE = '0';
  const ASSET_PURPOSE = '0';
  const inputAmount = 10;
  const inputPrice = 15;
  const principalAmount = _.round(inputAmount * inputPrice * 100);

  describe('#mint', async () => {
    it('No one than LoanKernel can mint', async () => {
      await expect(
        loanAssetTokenContract.connect(untangledAdminSigner)['mint(address,uint256)'](lenderSigner.address, 1)
      ).to.be.revertedWith(
        `AccessControl: account ${untangledAdminSigner.address.toLowerCase()} is missing role 0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6`
      );
    });

    it('Can not mint with invalid nonce', async () => {
      const orderAddresses = [
        securitizationPoolContract.address,
        stableCoin.address,
        loanRepaymentRouter.address,
        loanInterestTermsContract.address,
        relayer.address,
        borrowerSigner.address,
      ];

      const salt = genSalt();
      const riskScore = '50';
      expirationTimestamps = dayjs(new Date()).add(7, 'days').unix();

      const orderValues = [
        CREDITOR_FEE,
        ASSET_PURPOSE,
        parseEther(principalAmount.toString()),
        expirationTimestamps,
        salt,
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

      tokenIds = genLoanAgreementIds(
        loanRepaymentRouter.address,
        debtors,
        loanInterestTermsContract.address,
        termsContractParameters,
        salts
      );

      const [, , , , wrongLoanAssetTokenValidator] = await ethers.getSigners();

      await expect(loanKernel.fillDebtOrder(orderAddresses, orderValues, termsContractParameters,
        await Promise.all(tokenIds.map(async (tokenId) => {
          const nonce = (await loanAssetTokenContract.nonce(tokenId)).add(10).toNumber(); // wrong nonce

          return ({
            ...await generateLATMintPayload(
              loanAssetTokenContract,
              wrongLoanAssetTokenValidator,
              [tokenId],
              [nonce],
              defaultLoanAssetTokenValidator.address
            ),

            // tokenId,
            // nonce,
            // validator: defaultLoanAssetTokenValidator.address,
            // validateSignature: ,
          })
        }))
      )).to.be.revertedWith('LATValidator: invalid nonce');
    });

    it('Can not mint with wrong signature', async () => {
      const orderAddresses = [
        securitizationPoolContract.address,
        stableCoin.address,
        loanRepaymentRouter.address,
        loanInterestTermsContract.address,
        relayer.address,
        borrowerSigner.address,
      ];

      const salt = genSalt();
      const riskScore = '50';
      expirationTimestamps = dayjs(new Date()).add(7, 'days').unix();

      const orderValues = [
        CREDITOR_FEE,
        ASSET_PURPOSE,
        parseEther(principalAmount.toString()),
        expirationTimestamps,
        salt,
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

      tokenIds = genLoanAgreementIds(
        loanRepaymentRouter.address,
        debtors,
        loanInterestTermsContract.address,
        termsContractParameters,
        salts
      );

      const [, , , , wrongLoanAssetTokenValidator] = await ethers.getSigners();

      await expect(loanKernel.fillDebtOrder(orderAddresses, orderValues, termsContractParameters,
        await Promise.all(tokenIds.map(async (tokenId) => {
          const nonce = (await loanAssetTokenContract.nonce(tokenId)).toNumber();

          return ({
            ...await generateLATMintPayload(
              loanAssetTokenContract,
              wrongLoanAssetTokenValidator,
              [tokenId],
              [nonce],
              defaultLoanAssetTokenValidator.address
            ),

            // tokenId,
            // nonce,
            // validator: defaultLoanAssetTokenValidator.address,
            // validateSignature: ,
          })
        }))
      )).to.be.revertedWith('LATValidator: invalid validator signature');
    });

    it('Can not mint with wrong validator', async () => {
      const orderAddresses = [
        securitizationPoolContract.address,
        stableCoin.address,
        loanRepaymentRouter.address,
        loanInterestTermsContract.address,
        relayer.address,
        borrowerSigner.address,
      ];

      const salt = genSalt();
      const riskScore = '50';
      expirationTimestamps = dayjs(new Date()).add(7, 'days').unix();

      const orderValues = [
        CREDITOR_FEE,
        ASSET_PURPOSE,
        parseEther(principalAmount.toString()),
        expirationTimestamps,
        salt,
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

      tokenIds = genLoanAgreementIds(
        loanRepaymentRouter.address,
        debtors,
        loanInterestTermsContract.address,
        termsContractParameters,
        salts
      );

      const [, , , , wrongLoanAssetTokenValidator] = await ethers.getSigners();

      const latInfo = await generateLATMintPayload(loanAssetTokenContract, wrongLoanAssetTokenValidator, tokenIds, [0], wrongLoanAssetTokenValidator.address);

      await expect(loanKernel.fillDebtOrder(orderAddresses, orderValues, termsContractParameters,
        [latInfo]
      ), "Validator not whitelisted").to.be.revertedWith('LoanAssetToken: invalid validator');
    });

    it('Only Loan Kernel can mint with AA validator', async () => {
      const snap = await snapshot();

      // grant AA as Validator
      const [, , , , newValidatorSigner] = await ethers.getSigners();
      const aa = await upgrades.deployProxy(await ethers.getContractFactory("AAWallet"), []);
      await securitizationManager.registerValidator(aa.address);

      const orderAddresses = [
        securitizationPoolContract.address,
        stableCoin.address,
        loanRepaymentRouter.address,
        loanInterestTermsContract.address,
        relayer.address,
        borrowerSigner.address,
      ];

      const salt = genSalt();
      const riskScore = '50';
      expirationTimestamps = dayjs(new Date()).add(7, 'days').unix();

      const orderValues = [
        CREDITOR_FEE,
        ASSET_PURPOSE,
        parseEther(principalAmount.toString()),
        expirationTimestamps,
        salt,
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

      tokenIds = genLoanAgreementIds(
        loanRepaymentRouter.address,
        debtors,
        loanInterestTermsContract.address,
        termsContractParameters,
        salts
      );

      // 1: no newValidator in AA
      await expect(loanKernel.fillDebtOrder(orderAddresses, orderValues, termsContractParameters,
        await Promise.all(tokenIds.map(async (tokenId) => {
          const nonce = (await loanAssetTokenContract.nonce(tokenId)).toNumber();

          return ({
            ...await generateLATMintPayload(
              loanAssetTokenContract,
              newValidatorSigner,
              [tokenId],
              [nonce],
              aa.address
            ),

            // tokenId,
            // nonce,
            // validator: defaultLoanAssetTokenValidator.address,
            // validateSignature: ,
          })
        }))
      )).to.be.revertedWith("LATValidator: invalid validator signature");

      // add whitelist & try again
      await aa.grantRole(await aa.VALIDATOR_ROLE(), newValidatorSigner.address);
      await loanKernel.fillDebtOrder(orderAddresses, orderValues, termsContractParameters,
        await Promise.all(tokenIds.map(async (tokenId) => {
          const nonce = (await loanAssetTokenContract.nonce(tokenId)).toNumber();

          return ({
            ...await generateLATMintPayload(
              loanAssetTokenContract,
              newValidatorSigner,
              [tokenId],
              [nonce],
              aa.address
            ),

            // tokenId,
            // nonce,
            // validator: defaultLoanAssetTokenValidator.address,
            // validateSignature: ,
          })
        }))
      );

      const ownerOfAgreement = await loanAssetTokenContract.ownerOf(tokenIds[0]);
      expect(ownerOfAgreement).equal(securitizationPoolContract.address);

      const balanceOfPool = await loanAssetTokenContract.balanceOf(securitizationPoolContract.address);
      expect(balanceOfPool).equal(tokenIds.length);

      await snap.restore();
    });

    it('Only Loan Kernel can mint with validator signature', async () => {
      const orderAddresses = [
        securitizationPoolContract.address,
        stableCoin.address,
        loanRepaymentRouter.address,
        loanInterestTermsContract.address,
        relayer.address,
        borrowerSigner.address,
      ];

      const salt = genSalt();
      const riskScore = '50';
      expirationTimestamps = dayjs(new Date()).add(7, 'days').unix();

      const orderValues = [
        CREDITOR_FEE,
        ASSET_PURPOSE,
        parseEther(principalAmount.toString()),
        expirationTimestamps,
        salt,
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

      tokenIds = genLoanAgreementIds(
        loanRepaymentRouter.address,
        debtors,
        loanInterestTermsContract.address,
        termsContractParameters,
        salts
      );

      await loanKernel.fillDebtOrder(orderAddresses, orderValues, termsContractParameters,
        await Promise.all(tokenIds.map(async (tokenId) => {
          const nonce = (await loanAssetTokenContract.nonce(tokenId)).toNumber();

          return ({
            ...await generateLATMintPayload(
              loanAssetTokenContract,
              defaultLoanAssetTokenValidator,
              [tokenId],
              [nonce],
              defaultLoanAssetTokenValidator.address
            ),

            // tokenId,
            // nonce,
            // validator: defaultLoanAssetTokenValidator.address,
            // validateSignature: ,
          })
        }))
      )

      const ownerOfAgreement = await loanAssetTokenContract.ownerOf(tokenIds[0]);
      expect(ownerOfAgreement).equal(securitizationPoolContract.address);

      const balanceOfPool = await loanAssetTokenContract.balanceOf(securitizationPoolContract.address);
      expect(balanceOfPool).equal(tokenIds.length);
    });
  });

  describe('#info', async () => {
    it('getExpirationTimestamp', async () => {
      const data = await loanAssetTokenContract.getExpirationTimestamp(tokenIds[0]);
      expect(data.toString()).equal(expirationTimestamps.toString());
    });

    it('getRiskScore', async () => {
      const data = await loanAssetTokenContract.getRiskScore(tokenIds[0]);
      expect(data).equal(50);
    });

    it('getAssetPurpose', async () => {
      const data = await loanAssetTokenContract.getAssetPurpose(tokenIds[0]);
      expect(data).equal(parseInt(ASSET_PURPOSE));
    });

    it('getInterestRate', async () => {
      const data = await loanAssetTokenContract.getInterestRate(tokenIds[0]);
      expect(data.toString()).equal(interestRateFixedPoint(5).toString());
    });

    it('getExpectedRepaymentValues', async () => {
      const nextTimeStamps = dayjs(expirationTimestamps).add(1, 'days').unix();
      const data = await loanAssetTokenContract.getExpectedRepaymentValues(tokenIds[0], nextTimeStamps);

      expect(data.expectedPrincipal.toNumber()).equal(principalAmount);
      expect(data.expectedInterest.toString()).equal('0');
    });

    it('getTotalExpectedRepaymentValue', async () => {
      const nextTimeStamps = dayjs(expirationTimestamps).add(1, 'days').unix();
      const data = await loanAssetTokenContract.getTotalExpectedRepaymentValue(tokenIds[0], nextTimeStamps);

      expect(data.toNumber()).equal(principalAmount);
    });
  });

  describe('#burn', async () => {
    it('No one than LoanKernel contract can burn', async () => {
      await expect(loanAssetTokenContract.connect(untangledAdminSigner).burn(tokenIds[0])).to.be.revertedWith(
        `ERC721: caller is not token owner or approved`
      );
    });

    it('only LoanKernel contract can burn', async () => {
      const stablecoinBalanceOfPayerBefore = await stableCoin.balanceOf(untangledAdminSigner.address);
      expect(formatEther(stablecoinBalanceOfPayerBefore)).equal('99000.0');

      const stablecoinBalanceOfPoolBefore = await stableCoin.balanceOf(securitizationPoolContract.address);
      expect(formatEther(stablecoinBalanceOfPoolBefore)).equal('0.0');

      await loanRepaymentRouter
        .connect(untangledAdminSigner)
        .repayInBatch([tokenIds[0]], [parseEther('100')], stableCoin.address);

      await expect(loanAssetTokenContract.ownerOf(tokenIds[0])).to.be.revertedWith(`ERC721: invalid token ID`);

      const balanceOfPool = await loanAssetTokenContract.balanceOf(securitizationPoolContract.address);
      expect(balanceOfPool).equal(tokenIds.length - 1);

      const stablecoinBalanceOfPayerAfter = await stableCoin.balanceOf(untangledAdminSigner.address);
      expect(stablecoinBalanceOfPayerAfter).equal(stablecoinBalanceOfPayerBefore.sub(BigNumber.from(principalAmount)));

      const stablecoinBalanceOfPoolAfter = await stableCoin.balanceOf(securitizationPoolContract.address);
      expect(stablecoinBalanceOfPoolAfter.toNumber()).equal(principalAmount);
    });
  });
});
