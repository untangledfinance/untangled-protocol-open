const { ethers, upgrades } = require('hardhat');
const { deployments } = require('hardhat');
const _ = require('lodash');
const dayjs = require('dayjs');
const { expect } = require('./shared/expect.js');

const { BigNumber } = ethers;
const { parseEther, parseUnits, formatEther } = ethers.utils;

const { unlimitedAllowance, genSalt, generateEntryHash } = require('./utils.js');
const { setup } = require('./setup.js');

const ONE_DAY = 86400;
describe('AcceptedInvoiceToken', () => {
  let stableCoin;
  let acceptedInvoiceToken;
  let tokenIds = [];

  // Wallets
  let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer;
  before('create fixture', async () => {
    [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer] =
      await ethers.getSigners();

    ({ stableCoin, acceptedInvoiceToken } = await setup());

    await stableCoin.transfer(lenderSigner.address, parseEther('1000'));
    await stableCoin.transfer(borrowerSigner.address, parseEther('1000'));
  });

  let expirationTimestamps;
  const ASSET_PURPOSE = '0';

  describe('#mint', async () => {
    it('No one than Admin can mint', async () => {
      await expect(
        acceptedInvoiceToken.connect(lenderSigner)['mint(address,uint256)'](lenderSigner.address, 1000000)
      ).to.be.revertedWith(
        `AccessControl: account ${lenderSigner.address.toLowerCase()} is missing role 0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6`
      );
    });

    it('#createBatch', async () => {
      const salt = genSalt();
      const riskScore = '50';
      expirationTimestamps = dayjs(new Date()).add(7, 'days').unix();

      await expect(
        acceptedInvoiceToken
          .connect(untangledAdminSigner)
          .createBatch(
            [lenderSigner.address, borrowerSigner.address],
            [parseEther('100')],
            [stableCoin.address],
            [expirationTimestamps],
            [salt],
            [0, ASSET_PURPOSE]
          )
      ).to.be.revertedWith(`not permission to create token`);

      const INVOICE_CREATOR_ROLE = await acceptedInvoiceToken.INVOICE_CREATOR_ROLE();
      await acceptedInvoiceToken
        .connect(untangledAdminSigner)
        .grantRole(INVOICE_CREATOR_ROLE, untangledAdminSigner.address);

      const tokenId = generateEntryHash(
        lenderSigner.address,
        borrowerSigner.address,
        parseEther('100'),
        expirationTimestamps,
        salt
      );
      await acceptedInvoiceToken
        .connect(untangledAdminSigner)
        .createBatch(
          [lenderSigner.address, borrowerSigner.address],
          [parseEther('100')],
          [stableCoin.address],
          [expirationTimestamps],
          [salt],
          [0, ASSET_PURPOSE]
        );

      tokenIds.push(tokenId);

      const ownerOfAgreement = await acceptedInvoiceToken.ownerOf(tokenIds[0]);
      expect(ownerOfAgreement).equal(borrowerSigner.address);
    });
  });

  describe('#info', async () => {
    it('getExpirationTimestamp', async () => {
      const data = await acceptedInvoiceToken.getExpirationTimestamp(tokenIds[0]);
      expect(data.toString()).equal(expirationTimestamps.toString());
    });

    it('getRiskScore', async () => {
      const data = await acceptedInvoiceToken.getRiskScore(tokenIds[0]);
      expect(data).equal(0);
    });

    it('getAssetPurpose', async () => {
      const data = await acceptedInvoiceToken.getAssetPurpose(tokenIds[0]);
      expect(data).equal(parseInt(ASSET_PURPOSE));
    });

    it('getInterestRate', async () => {
      const data = await acceptedInvoiceToken.getInterestRate(tokenIds[0]);
      expect(data.toString()).equal('0');
    });

    it('getExpectedRepaymentValues', async () => {
      const nextTimeStamps = dayjs(new Date()).add(1, 'days').unix();
      const data = await acceptedInvoiceToken.getExpectedRepaymentValues(tokenIds[0], nextTimeStamps);

      expect(formatEther(data[0])).equal('100.0');
      expect(data[1].toString()).equal('0');
    });

    it('getTotalExpectedRepaymentValue', async () => {
      const nextTimeStamps = dayjs(new Date()).add(1, 'days').unix();
      const data = await acceptedInvoiceToken.getTotalExpectedRepaymentValue(tokenIds[0], nextTimeStamps);

      expect(formatEther(data)).equal('100.0');
    });

    it('getFiatAmount', async () => {
      const data = await acceptedInvoiceToken.getFiatAmount(tokenIds[0]);

      expect(formatEther(data)).equal('100.0');
    });

    it('isPaid', async () => {
      const data = await acceptedInvoiceToken.isPaid(tokenIds[0]);

      expect(data).equal(false);
    });
  });

  describe('#payInBatch', async () => {
    it('should pay successfully', async () => {
      await stableCoin.connect(borrowerSigner).approve(acceptedInvoiceToken.address, unlimitedAllowance);
      await acceptedInvoiceToken.connect(borrowerSigner).payInBatch([tokenIds[0]], [parseEther('90')]);
    });

    it('should pay the rest successfully', async () => {
      await acceptedInvoiceToken.connect(borrowerSigner).payInBatch([tokenIds[0]], [parseEther('10')]);
    });

    it('isPaid', async () => {
      const data = await acceptedInvoiceToken.isPaid(tokenIds[0]);

      expect(data).equal(true);
    });
  });
});
