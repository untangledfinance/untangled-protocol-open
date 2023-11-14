const { ethers, upgrades } = require('hardhat');
const { deployments } = require('hardhat');
const _ = require('lodash');
const dayjs = require('dayjs');
const { expect } = require('chai');
const { impersonateAccount, setBalance } = require('@nomicfoundation/hardhat-network-helpers');

const { BigNumber } = ethers;
const { parseEther, parseUnits, formatEther, formatBytes32String } = ethers.utils;

const {
  unlimitedAllowance,
  ZERO_ADDRESS,
  genLoanAgreementIds,
  saltFromOrderValues,
  debtorsFromOrderAddresses,
  packTermsContractParameters,
  interestRateFixedPoint,
  genSalt,
  generateLATMintPayload
} = require('./utils.js');
const { setup } = require('./setup.js');

const { POOL_ADMIN_ROLE } = require('./constants.js');
const { constants, utils } = require('ethers');

const ONE_DAY = 86400;
describe('LoanKernel', () => {
  let stableCoin;
  let registry;
  let loanAssetTokenContract;
  let loanInterestTermsContract;
  let defaultLoanAssetTokenValidator;
  let loanRegistry;
  let loanKernel;
  let loanRepaymentRouter;
  let securitizationManager;
  let securitizationPoolContract;
  let securitizationPoolValueService;
  let securitizationPoolImpl;
  let tokenIds;

  // Wallets
  let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer;
  before('create fixture', async () => {
    [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer] =
      await ethers.getSigners();

    ({
      stableCoin,
      registry,
      loanAssetTokenContract,
      defaultLoanAssetTokenValidator,
      loanInterestTermsContract,
      loanRegistry,
      loanKernel,
      loanRepaymentRouter,
      securitizationManager,
      securitizationPoolValueService,
      securitizationPoolImpl,
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
        .newPoolInstance(stableCoin.address, '100000', poolCreatorSigner.address,  utils.keccak256(Date.now()));
      const receipt = await transaction.wait();
      const [securitizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;

      securitizationPoolContract = await ethers.getContractAt('SecuritizationPool', securitizationPoolAddress);
    });
  });

  let expirationTimestamps;
  const CREDITOR_FEE = '0';
  const ASSET_PURPOSE = '0';
  const inputAmount = 10;
  const inputPrice = 15;
  const principalAmount = _.round(inputAmount * inputPrice * 100);

  describe('#fillDebtOrder', async () => {
    it('No one than LoanKernel can mint', async () => {
      await expect(
        loanAssetTokenContract.connect(untangledAdminSigner)['mint(address,uint256)'](lenderSigner.address, 1)
      ).to.be.revertedWith(
        `AccessControl: account ${untangledAdminSigner.address.toLowerCase()} is missing role 0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6`
      );
    });

    it('CREDITOR is zero address', async () => {
      const orderAddresses = [
        ZERO_ADDRESS,
        stableCoin.address,
        loanRepaymentRouter.address,
        loanInterestTermsContract.address,
        relayer.address,
        borrowerSigner.address,
      ];
      await expect(loanKernel.fillDebtOrder(orderAddresses, [], [], [])).to.be.revertedWith(
        `CREDITOR is zero address.`
      );
    });

    it('REPAYMENT_ROUTER is zero address', async () => {
      const orderAddresses = [
        securitizationPoolContract.address,
        stableCoin.address,
        ZERO_ADDRESS,
        loanInterestTermsContract.address,
        relayer.address,
        borrowerSigner.address,
      ];
      await expect(loanKernel.fillDebtOrder(orderAddresses, [], [], [])).to.be.revertedWith(
        `REPAYMENT_ROUTER is zero address.`
      );
    });

    it('TERM_CONTRACT is zero address', async () => {
      const orderAddresses = [
        securitizationPoolContract.address,
        stableCoin.address,
        loanRepaymentRouter.address,
        ZERO_ADDRESS,
        relayer.address,
        borrowerSigner.address,
      ];
      await expect(loanKernel.fillDebtOrder(orderAddresses, [], [], [])).to.be.revertedWith(
        `TERM_CONTRACT is zero address.`
      );
    });

    it('PRINCIPAL_TOKEN_ADDRESS is zero address', async () => {
      const orderAddresses = [
        securitizationPoolContract.address,
        ZERO_ADDRESS,
        loanRepaymentRouter.address,
        loanInterestTermsContract.address,
        relayer.address,
        borrowerSigner.address,
      ];
      await expect(loanKernel.fillDebtOrder(orderAddresses, [], [], [])).to.be.revertedWith(
        `PRINCIPAL_TOKEN_ADDRESS is zero address.`
      );
    });

    it('LoanKernel: Invalid Term Contract params', async () => {
      const orderAddresses = [
        securitizationPoolContract.address,
        stableCoin.address,
        loanRepaymentRouter.address,
        loanInterestTermsContract.address,
        relayer.address,
        borrowerSigner.address,
      ];
      await expect(loanKernel.fillDebtOrder(orderAddresses, [], [], [])).to.be.revertedWith(
        `LoanKernel: Invalid Term Contract params`
      );
    });

    it('LoanKernel: Invalid LAT Token Id', async () => {
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

      const tokenIds = ['0x944b447816387dc1f14b1a81dc4d95a77f588c214732772d921e146acd456b2b'];

      await expect(
        loanKernel.fillDebtOrder(orderAddresses, orderValues, termsContractParameters,
          await Promise.all(tokenIds.map(async (x) => ({
            ...await generateLATMintPayload(
              loanAssetTokenContract,
              defaultLoanAssetTokenValidator,
              [x],
              [(await loanAssetTokenContract.nonce(x)).toNumber()],
              defaultLoanAssetTokenValidator.address
            )
          })))
        )
      ).to.be.revertedWith(`LoanKernel: Invalid LAT Token Id`);
    });

    it('Execute fillDebtOrder successfully', async () => {
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
        await Promise.all(tokenIds.map(async (x) => ({
          ...await generateLATMintPayload(
            loanAssetTokenContract,
            defaultLoanAssetTokenValidator,
            [x],
            [(await loanAssetTokenContract.nonce(x)).toNumber()],
            defaultLoanAssetTokenValidator.address
          )
        })))
      );

      const ownerOfAgreement = await loanAssetTokenContract.ownerOf(tokenIds[0]);
      expect(ownerOfAgreement).equal(securitizationPoolContract.address);

      const balanceOfPool = await loanAssetTokenContract.balanceOf(securitizationPoolContract.address);
      expect(balanceOfPool).equal(tokenIds.length);

      await expect(
        loanKernel.fillDebtOrder(orderAddresses, orderValues, termsContractParameters,
          await Promise.all(tokenIds.map(async (x) => ({
            ...await generateLATMintPayload(
              loanAssetTokenContract,
              defaultLoanAssetTokenValidator,
              [x],
              [(await loanAssetTokenContract.nonce(x)).toNumber()],
              defaultLoanAssetTokenValidator.address
            )
          })))
        )
      ).to.be.revertedWith(`ERC721: token already minted`);
    });
  });

  describe('Loan registry', async () => {
    it('#getLoanDebtor', async () => {
      const result = await loanRegistry.getLoanDebtor(tokenIds[0]);

      expect(result).equal(borrowerSigner.address);
    });

    it('#getLoanTermParams', async () => {
      const result = await loanRegistry.getLoanTermParams(tokenIds[0]);

      expect(result).equal('0x00000000000000000000003a9800c35010000000000000000000000f00200000');
    });

    it('#getDebtor', async () => {
      const result = await loanRegistry.getDebtor(tokenIds[0]);

      expect(result).equal(borrowerSigner.address);
    });

    it('#principalPaymentInfo', async () => {
      const result = await loanRegistry.principalPaymentInfo(tokenIds[0]);

      expect(result.pTokenAddress).equal(stableCoin.address);
      expect(result.pAmount.toNumber()).equal(0);
    });
  });

  describe('#concludeLoan', async () => {
    it('No one than LoanKernel contract can burn', async () => {
      await expect(loanAssetTokenContract.connect(untangledAdminSigner).burn(tokenIds[0])).to.be.revertedWith(
        `ERC721: caller is not token owner or approved`
      );
    });

    it('LoanKernel: Invalid creditor account', async () => {
      await impersonateAccount(loanRepaymentRouter.address);
      await setBalance(loanRepaymentRouter.address, ethers.utils.parseEther('1'));
      const signer = await ethers.getSigner(loanRepaymentRouter.address);
      await expect(
        loanKernel.connect(signer).concludeLoans([ZERO_ADDRESS], [tokenIds[0]], loanInterestTermsContract.address)
      ).to.be.revertedWith(`Invalid creditor account.`);
    });

    it('LoanKernel: Invalid agreement id', async () => {
      const signer = await ethers.getSigner(loanRepaymentRouter.address);
      await expect(
        loanKernel.connect(signer).concludeLoans(
          [securitizationPoolContract.address],
          [formatBytes32String('')],
          loanInterestTermsContract.address
        )
      ).to.be.revertedWith(`Invalid agreement id.`);
    });

    it('LoanKernel: Invalid terms contract', async () => {
      const signer = await ethers.getSigner(loanRepaymentRouter.address);
      await expect(
        loanKernel.connect(signer).concludeLoans([securitizationPoolContract.address], [tokenIds[0]], ZERO_ADDRESS)
      ).to.be.revertedWith(`Invalid terms contract.`);
    });

    it('Cannot conclude agreement id if caller is not LoanRepaymentRouter', async () => {
      await expect(
        loanKernel.concludeLoans([securitizationPoolContract.address], [tokenIds[0]], loanInterestTermsContract.address)
      ).to.be.revertedWith('LoanKernel: Only LoanRepaymentRouter');
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
      expect(stablecoinBalanceOfPayerAfter).equal(stablecoinBalanceOfPayerBefore.sub(BigNumber.from('0')));

      const stablecoinBalanceOfPoolAfter = await stableCoin.balanceOf(securitizationPoolContract.address);
      expect(stablecoinBalanceOfPoolAfter.toNumber()).equal(0);
    });

    it('Cannot conclude agreement id again', async () => {
      const signer = await ethers.getSigner(loanRepaymentRouter.address);
      await expect(
        loanKernel.connect(signer).concludeLoans([securitizationPoolContract.address], [tokenIds[0]], loanInterestTermsContract.address)
      ).to.be.revertedWith(`ERC721: invalid token ID`);
    });
  });
});
