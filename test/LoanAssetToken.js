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

describe('LoanAssetToken', () => {
    let stableCoin;
    let registry;
    let loanAssetTokenContract;
    let loanInterestTermsContract = {
        address: ZERO_ADDRESS,
    };
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
    // Wallets
    let untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer;
    before('create fixture', async () => {
        [untangledAdminSigner, poolCreatorSigner, originatorSigner, borrowerSigner, lenderSigner, relayer] =
            await ethers.getSigners();

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
                            debtCeiling: parseEther('1000').toString(),
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
    });

    describe('#Securitization Manager', async () => {
        it('Should set up TGE for SOT successfully', async () => {
            const openingTime = dayjs(new Date()).unix();
            const closingTime = dayjs(new Date()).add(7, 'days').unix();
            const rate = 2;
            const totalCapOfToken = parseEther('100000');
            const initialInterest = 10000;
            const finalInterest = 10000;
            const timeInterval = 1 * 24 * 3600; // seconds
            const amountChangeEachInterval = 0;
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
                    initialInterest,
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

        it('Should set up TGE for JOT successfully', async () => {
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

            jotMintedIncreasingInterestTGE = await ethers.getContractAt('MintedIncreasingInterestTGE', tgeAddress);

            const [jotTokenAddress] = receipt.events.find((e) => e.event == 'NewNotesTokenCreated').args;
            expect(jotTokenAddress).to.be.properAddress;

            jotToken = await ethers.getContractAt('NoteToken', jotTokenAddress);
        });

        it('Should buy tokens failed if buy sot first', async () => {
            await stableCoin.connect(lenderSigner).approve(mintedIncreasingInterestTGE.address, unlimitedAllowance);

            await expect(
                securitizationManager
                    .connect(lenderSigner)
                    .buyTokens(mintedIncreasingInterestTGE.address, parseEther('100'))
            ).to.be.revertedWith(`Crowdsale: sale not started`);
        });

        it('Should buy tokens successfully', async () => {
            await stableCoin.connect(lenderSigner).approve(mintedIncreasingInterestTGE.address, unlimitedAllowance);

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

            const sotValue = await distributionAssessor.calcCorrespondingTotalAssetValue(
                sotToken.address,
                lenderSigner.address
            );
            expect(formatEther(sotValue)).equal('100.0');
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

            tokenIds = genLoanAgreementIds(
                loanRepaymentRouter.address,
                debtors,
                loanInterestTermsContract.address,
                termsContractParameters,
                salts
            );

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
            const snap = await snapshot();

            // grant AA as Validator
            const [, , , , newValidatorSigner] = await ethers.getSigners();
            const aa = await upgrades.deployProxy(await ethers.getContractFactory('AAWallet'), []);
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

            tokenIds = genLoanAgreementIds(
                loanRepaymentRouter.address,
                debtors,
                loanInterestTermsContract.address,
                termsContractParameters,
                salts
            );

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
                loanInterestTermsContract.address,
                relayer.address,
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

            tokenIds = genLoanAgreementIds(
                loanRepaymentRouter.address,
                debtors,
                loanInterestTermsContract.address,
                termsContractParameters,
                salts
            );

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
            expect(tokenURI).to.equal(`${LAT_BASE_URI}${tokenIds[0]}`);
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
            expect(tokenURI).to.equal(`https://untangled.finance/lat/${tokenIds[0]}`);
        });

        describe('#info', async () => {
            it('getExpirationTimestamp', async () => {
                const data = await securitizationPoolContract.getEntry(tokenIds[0]);
                expect(data.expirationTimestamp.toString()).equal(expirationTimestamps.toString());
            });

            it('getRiskScore', async () => {
                const data = await securitizationPoolContract.getEntry(tokenIds[0]);
                expect(data.riskScore).equal(1);
            });

            it('getAssetPurpose', async () => {
                const data = await securitizationPoolContract.getEntry(tokenIds[0]);
                expect(data.assetPurpose).equal(parseInt(ASSET_PURPOSE));
            });

            it('getInterestRate', async () => {
                const data = await securitizationPoolContract.unpackParamsForAgreementID(tokenIds[0]);
                expect(data.interestRate.toString()).equal(interestRateFixedPoint(5).toString());
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
