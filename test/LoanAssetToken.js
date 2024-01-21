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
    getPoolByAddress,
    formatFillDebtOrderParams,
    ZERO_ADDRESS,
} = require('./utils.js');
const { setup } = require('./setup.js');

const { POOL_ADMIN_ROLE, ORIGINATOR_ROLE } = require('./constants.js');
const { utils } = require('ethers');
const { presignedMintMessage } = require('./shared/uid-helper.js');
const { SaleType } = require('./shared/constants.js');
const { LAT_BASE_URI } = require('./shared/constants');
const UntangledProtocol = require('./shared/untangled-protocol');

describe('LoanAssetToken', () => {
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
    let mintedIncreasingInterestTGE;
    let jotMintedIncreasingInterestTGE;
    let securitizationPoolValueService;
    let distributionAssessor;
    let chainId;
    let untangledProtocol;
    // Wallets
    let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer;
    before('create fixture', async () => {
        [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer] =
            await ethers.getSigners();

        const contracts = await setup();
        untangledProtocol = UntangledProtocol.bind(contracts);
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

        await stableCoin.transfer(lenderSigner.address, parseEther('1000'));

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

    describe('#Initialize suit', async () => {
        it('Create pool & TGEs', async () => {
            const OWNER_ROLE = await securitizationManager.OWNER_ROLE();
            await securitizationManager.setRoleAdmin(POOL_ADMIN_ROLE, OWNER_ROLE);

            await securitizationManager.grantRole(OWNER_ROLE, borrowerSigner.address);
            await securitizationManager.connect(borrowerSigner).grantRole(POOL_ADMIN_ROLE, poolCreatorSigner.address);

            const poolParams = {
                currency: 'cUSD',
                minFirstLossCushion: 10,
                validatorRequired: true,
                debtCeiling: 1000,
            };

            const oneDayInSecs = 1 * 24 * 3600;
            const halfOfADay = oneDayInSecs / 2;
            const riskScores = [{
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
            }];

            const openingTime = dayjs(new Date()).unix();
            const closingTime = dayjs(new Date()).add(7, 'days').unix();
            const rate = 2;
            const totalCapOfToken = parseEther('100000');
            const initialInterest = 10000;
            const finalInterest = 10000;
            const timeInterval = 1 * 24 * 3600; // seconds
            const amountChangeEachInterval = 0;
            const prefixOfNoteTokenSaleName = 'Ticker_';
            const sotInfo = {
                issuerTokenController: untangledAdminSigner.address,
                saleType: SaleType.MINTED_INCREASING_INTEREST,
                minBidAmount: parseEther('50'),
                openingTime,
                closingTime,
                rate,
                cap: totalCapOfToken,
                initialInterest,
                finalInterest,
                timeInterval,
                amountChangeEachInterval,
                ticker: prefixOfNoteTokenSaleName,
            };

            const initialJOTAmount = parseEther('1');
            const jotInfo = {
                issuerTokenController: untangledAdminSigner.address,
                minBidAmount: parseEther('50'),
                saleType: SaleType.NORMAL_SALE,
                longSale: true,
                ticker: prefixOfNoteTokenSaleName,
                openingTime: openingTime,
                closingTime: closingTime,
                rate: rate,
                cap: totalCapOfToken,
                initialJOTAmount,
            };
            const [poolAddress, sotCreated, jotCreated] = await untangledProtocol.createFullPool(poolCreatorSigner, poolParams, riskScores, sotInfo, jotInfo);
            securitizationPoolContract = await getPoolByAddress(poolAddress);
            mintedIncreasingInterestTGE = await ethers.getContractAt('MintedIncreasingInterestTGE', sotCreated.sotTGEAddress);
            jotMintedIncreasingInterestTGE = await ethers.getContractAt('MintedIncreasingInterestTGE', jotCreated.jotTGEAddress);
        });

        it('Should buy tokens successfully', async () => {
            await untangledProtocol.buyToken(lenderSigner, jotMintedIncreasingInterestTGE.address, parseEther('100'));

            await untangledProtocol.buyToken(lenderSigner, mintedIncreasingInterestTGE.address, parseEther('100'));

            const stablecoinBalanceOfPayerAfter = await stableCoin.balanceOf(lenderSigner.address);
            expect(formatEther(stablecoinBalanceOfPayerAfter)).equal('800.0');

            expect(formatEther(await stableCoin.balanceOf(securitizationPoolContract.address))).equal('200.0');
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
                borrowerSigner.address,
            ];

            const salt = genSalt();
            const riskScore = '1';
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

            tokenIds = genLoanAgreementIds(loanRepaymentRouter.address, debtors, termsContractParameters, salts);

            const [, , , , wrongLoanAssetTokenValidator] = await ethers.getSigners();

            await expect(
                loanKernel.fillDebtOrder(
                    formatFillDebtOrderParams(
                        orderAddresses,
                        orderValues,
                        termsContractParameters,
                        await Promise.all(
                            tokenIds.map(async (tokenId) => {
                                const nonce = (await loanAssetTokenContract.nonce(tokenId)).add(10).toNumber(); // wrong nonce

                                return {
                                    ...(await generateLATMintPayload(
                                        loanAssetTokenContract,
                                        wrongLoanAssetTokenValidator,
                                        [tokenId],
                                        [nonce],
                                        defaultLoanAssetTokenValidator.address
                                    )),

                                    // tokenId,
                                    // nonce,
                                    // validator: defaultLoanAssetTokenValidator.address,
                                    // validateSignature: ,
                                };
                            })
                        )
                    )
                )
            ).to.be.revertedWith('LATValidator: invalid nonce');
        });

        it('Can not mint with wrong signature', async () => {
            const orderAddresses = [
                securitizationPoolContract.address,
                stableCoin.address,
                loanRepaymentRouter.address,
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

            tokenIds = genLoanAgreementIds(loanRepaymentRouter.address, debtors, termsContractParameters, salts);

            const [, , , , wrongLoanAssetTokenValidator] = await ethers.getSigners();

            await expect(
                loanKernel.fillDebtOrder(
                    formatFillDebtOrderParams(
                        orderAddresses,
                        orderValues,
                        termsContractParameters,
                        await Promise.all(
                            tokenIds.map(async (tokenId) => {
                                const nonce = (await loanAssetTokenContract.nonce(tokenId)).toNumber();

                                return {
                                    ...(await generateLATMintPayload(
                                        loanAssetTokenContract,
                                        wrongLoanAssetTokenValidator,
                                        [tokenId],
                                        [nonce],
                                        defaultLoanAssetTokenValidator.address
                                    )),

                                    // tokenId,
                                    // nonce,
                                    // validator: defaultLoanAssetTokenValidator.address,
                                    // validateSignature: ,
                                };
                            })
                        )
                    )
                )
            ).to.be.revertedWith('LATValidator: invalid validator signature');
        });

        it('Can not mint with wrong validator', async () => {
            const orderAddresses = [
                securitizationPoolContract.address,
                stableCoin.address,
                loanRepaymentRouter.address,
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

            tokenIds = genLoanAgreementIds(loanRepaymentRouter.address, debtors, termsContractParameters, salts);

            const [, , , , wrongLoanAssetTokenValidator] = await ethers.getSigners();

            const latInfo = await generateLATMintPayload(
                loanAssetTokenContract,
                wrongLoanAssetTokenValidator,
                tokenIds,
                [0],
                wrongLoanAssetTokenValidator.address
            );

            await expect(
                loanKernel.fillDebtOrder(
                    formatFillDebtOrderParams(orderAddresses, orderValues, termsContractParameters, [latInfo])
                ),
                'Validator not whitelisted'
            ).to.be.revertedWith('LATValidator: invalid validator');
        });

        it('Only Loan Kernel can mint with AA validator', async () => {
            await securitizationPoolContract
                .connect(poolCreatorSigner)
                .grantRole(ORIGINATOR_ROLE, untangledAdminSigner.address);
            const snap = await snapshot();

            // grant AA as Validator
            const [, , , , newValidatorSigner] = await ethers.getSigners();
            const aa = await upgrades.deployProxy(await ethers.getContractFactory('AAWallet'), []);
            await securitizationManager.registerValidator(aa.address);

            const orderAddresses = [
                securitizationPoolContract.address,
                stableCoin.address,
                loanRepaymentRouter.address,
                borrowerSigner.address,
            ];

            const salt = genSalt();
            const riskScore = '1';
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

            tokenIds = genLoanAgreementIds(loanRepaymentRouter.address, debtors, termsContractParameters, salts);

            // 1: no newValidator in AA
            await expect(
                loanKernel.fillDebtOrder(
                    formatFillDebtOrderParams(
                        orderAddresses,
                        orderValues,
                        termsContractParameters,
                        await Promise.all(
                            tokenIds.map(async (tokenId) => {
                                const nonce = (await loanAssetTokenContract.nonce(tokenId)).toNumber();

                                return {
                                    ...(await generateLATMintPayload(
                                        loanAssetTokenContract,
                                        newValidatorSigner,
                                        [tokenId],
                                        [nonce],
                                        aa.address
                                    )),

                                    // tokenId,
                                    // nonce,
                                    // validator: defaultLoanAssetTokenValidator.address,
                                    // validateSignature: ,
                                };
                            })
                        )
                    )
                )
            ).to.be.revertedWith('LATValidator: invalid validator signature');

            // add whitelist & try again
            await aa.grantRole(await aa.VALIDATOR_ROLE(), newValidatorSigner.address);
            await loanKernel.fillDebtOrder(
                formatFillDebtOrderParams(
                    orderAddresses,
                    orderValues,
                    termsContractParameters,
                    await Promise.all(
                        tokenIds.map(async (tokenId) => {
                            const nonce = (await loanAssetTokenContract.nonce(tokenId)).toNumber();

                            return {
                                ...(await generateLATMintPayload(
                                    loanAssetTokenContract,
                                    newValidatorSigner,
                                    [tokenId],
                                    [nonce],
                                    aa.address
                                )),

                                // tokenId,
                                // nonce,
                                // validator: defaultLoanAssetTokenValidator.address,
                                // validateSignature: ,
                            };
                        })
                    )
                )
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
                borrowerSigner.address,
            ];

            const salt = genSalt();
            const riskScore = '1';
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

            tokenIds = genLoanAgreementIds(loanRepaymentRouter.address, debtors, termsContractParameters, salts);

            await loanKernel.fillDebtOrder(
                formatFillDebtOrderParams(
                    orderAddresses,
                    orderValues,
                    termsContractParameters,
                    await Promise.all(
                        tokenIds.map(async (tokenId) => {
                            const nonce = (await loanAssetTokenContract.nonce(tokenId)).toNumber();

                            return {
                                ...(await generateLATMintPayload(
                                    loanAssetTokenContract,
                                    defaultLoanAssetTokenValidator,
                                    [tokenId],
                                    [nonce],
                                    defaultLoanAssetTokenValidator.address
                                )),

                                // tokenId,
                                // nonce,
                                // validator: defaultLoanAssetTokenValidator.address,
                                // validateSignature: ,
                            };
                        })
                    )
                )
            );

            const ownerOfAgreement = await loanAssetTokenContract.ownerOf(tokenIds[0]);
            expect(ownerOfAgreement).equal(securitizationPoolContract.address);

            const balanceOfPool = await loanAssetTokenContract.balanceOf(securitizationPoolContract.address);
            expect(balanceOfPool).equal(tokenIds.length);
        });

        it('Correct token uri', async () => {
            const tokenURI = await loanAssetTokenContract.tokenURI(tokenIds[0]);
            expect(tokenURI).to.equal(`${LAT_BASE_URI}${tokenIds[0]}?chain_id=${chainId}`);
        });

        it('Should revert if setBaseURI by a wallet which is NOT admin', async () => {
            await expect(
                loanAssetTokenContract.connect(lenderSigner).setBaseURI('https://untangled.finance/lat/')
            ).to.be.revertedWith(
                `AccessControl: account ${lenderSigner.address.toLowerCase()} is missing role 0x0000000000000000000000000000000000000000000000000000000000000000`
            );
        });

        it('Change base uri successfully', async () => {
            await loanAssetTokenContract.connect(untangledAdminSigner).setBaseURI('https://untangled.finance/lat/');
            const tokenURI = await loanAssetTokenContract.tokenURI(tokenIds[0]);
            expect(tokenURI).to.equal(`https://untangled.finance/lat/${tokenIds[0]}?chain_id=${chainId}`);
        });

        describe('#info', async () => {
            it('getExpirationTimestamp', async () => {
                const data = await securitizationPoolContract.getAsset(tokenIds[0]);
                expect(data.expirationTimestamp.toString()).equal(expirationTimestamps.toString());
            });

            it('getRiskScore', async () => {
                const data = await securitizationPoolContract.getAsset(tokenIds[0]);
                expect(data.risk).equal(1);
            });

            it('getAssetPurpose', async () => {
                const data = await securitizationPoolContract.getAsset(tokenIds[0]);
                expect(data.assetPurpose).equal(parseInt(ASSET_PURPOSE));
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
                expect(stablecoinBalanceOfPayerBefore).to.closeTo(parseEther('99000'), parseEther('0.001'));

                const stablecoinBalanceOfPoolBefore = await stableCoin.balanceOf(securitizationPoolContract.address);
                expect(stablecoinBalanceOfPoolBefore).to.closeTo(parseEther('200'), parseEther('0.001'));

                await loanRepaymentRouter
                    .connect(untangledAdminSigner)
                    .repayInBatch([tokenIds[0]], [parseEther('100')], stableCoin.address);

                await expect(loanAssetTokenContract.ownerOf(tokenIds[0])).to.be.revertedWith(
                    `ERC721: invalid token ID`
                );

                const balanceOfPool = await loanAssetTokenContract.balanceOf(securitizationPoolContract.address);
                expect(balanceOfPool).equal(tokenIds.length - 1);

                const stablecoinBalanceOfPayerAfter = await stableCoin.balanceOf(untangledAdminSigner.address);
                expect(stablecoinBalanceOfPayerAfter).equal(stablecoinBalanceOfPayerBefore.sub('14250'));

                const stablecoinBalanceOfPoolAfter = await stableCoin.balanceOf(securitizationPoolContract.address);
                expect(stablecoinBalanceOfPoolAfter).to.closeTo(parseEther('200'), parseEther('0.001'));
            });
        });
    });
});
