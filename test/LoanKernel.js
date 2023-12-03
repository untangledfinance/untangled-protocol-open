const { ethers, artifacts } = require('hardhat');
const _ = require('lodash');
const dayjs = require('dayjs');
const { expect } = require('chai');
const { impersonateAccount, setBalance } = require('@nomicfoundation/hardhat-network-helpers');

const { constants, BigNumber } = ethers;
const { parseEther, formatEther, formatBytes32String } = ethers.utils;
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
    generateLATMintPayload,
    getPoolByAddress,
    formatFillDebtOrderParams,
} = require('./utils.js');
const { setup } = require('./setup.js');
const { SaleType } = require('./shared/constants.js');

const { POOL_ADMIN_ROLE } = require('./constants.js');
const { utils } = require('ethers');
const { ORIGINATOR_ROLE } = require('./constants');

const RATE_SCALING_FACTOR = 10 ** 4;

describe('LoanKernel', () => {
    let stableCoin;
    let loanAssetTokenContract;
    let loanInterestTermsContract;
    let loanKernel;
    let loanRepaymentRouter;
    let securitizationManager;
    let securitizationPoolContract;
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
    let defaultLoanAssetTokenValidator;
    let loanRegistry;

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
            defaultLoanAssetTokenValidator,
            loanRegistry,
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

            const salt = utils.keccak256(Date.now());

            // Create new pool
            let transaction = await securitizationManager
                .connect(poolCreatorSigner)

                .newPoolInstance(
                    salt,

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
                                ],
                            },
                        ],
                        [
                            {
                                currency: stableCoin.address,
                                minFirstLossCushion: '100000',
                                validatorRequired: true,
                            },
                        ]
                    )
                );

            let receipt = await transaction.wait();
            let [securitizationPoolAddress] = receipt.events.find((e) => e.event == 'NewPoolCreated').args;

            // expect address, create2
            const { bytecode } = await artifacts.readArtifact('TransparentUpgradeableProxy');
            // abi.encodePacked(
            //     type(TransparentUpgradeableProxy).creationCode,
            //     abi.encode(_poolImplAddress, address(this), '')
            // )
            const initCodeHash = utils.keccak256(
                utils.solidityPack(
                    ['bytes', 'bytes'],
                    [
                        `${bytecode}`,
                        utils.defaultAbiCoder.encode(
                            ['address', 'address', 'bytes'],
                            [securitizationPoolImpl.address, securitizationManager.address, Buffer.from([])]
                        ),
                    ]
                )
            );

            const create2 = utils.getCreate2Address(securitizationManager.address, salt, initCodeHash);
            expect(create2).to.be.eq(securitizationPoolAddress);

            securitizationPoolContract = await getPoolByAddress(securitizationPoolAddress);
            await securitizationPoolContract
                .connect(poolCreatorSigner)
                .grantRole(ORIGINATOR_ROLE, originatorSigner.address);

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
                securitizationManager
                    .connect(lenderSigner)
                    .buyTokens(mintedIncreasingInterestTGE.address, parseEther('100'))
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

    let expirationTimestamps;
    const CREDITOR_FEE = '0';
    const ASSET_PURPOSE_LOAN = '0';
    const ASSET_PURPOSE_INVOICE = '1';
    const inputAmount = 10;
    const inputPrice = 15;
    const principalAmount = 10000000000000000000;

    describe('#LoanKernel', async () => {
        it('No one than LoanKernel can mint', async () => {
            await expect(
                loanAssetTokenContract.connect(untangledAdminSigner)['mint(address,uint256)'](lenderSigner.address, 1)
            ).to.be.revertedWith(
                `AccessControl: account ${untangledAdminSigner.address.toLowerCase()} is missing role 0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6`
            );
        });

        it('SECURITIZATION_POOL is zero address', async () => {
            const orderAddresses = [
                ZERO_ADDRESS,
                stableCoin.address,
                loanRepaymentRouter.address,
                loanInterestTermsContract.address,
                relayer.address,
                borrowerSigner.address,
            ];
            await expect(
                loanKernel.fillDebtOrder(formatFillDebtOrderParams(orderAddresses, [], [], []))
            ).to.be.revertedWith(`SECURITIZATION_POOL is zero address.`);
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
            await expect(
                loanKernel.fillDebtOrder(formatFillDebtOrderParams(orderAddresses, [], [], []))
            ).to.be.revertedWith(`REPAYMENT_ROUTER is zero address.`);
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
            await expect(
                loanKernel.fillDebtOrder(formatFillDebtOrderParams(orderAddresses, [], [], []))
            ).to.be.revertedWith(`TERM_CONTRACT is zero address.`);
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
            await expect(
                loanKernel.fillDebtOrder(formatFillDebtOrderParams(orderAddresses, [], [], []))
            ).to.be.revertedWith(`PRINCIPAL_TOKEN_ADDRESS is zero address.`);
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
            await expect(
                loanKernel.fillDebtOrder(formatFillDebtOrderParams(orderAddresses, [], [], []))
            ).to.be.revertedWith(`LoanKernel: Invalid Term Contract params`);
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
                ASSET_PURPOSE_LOAN,
                principalAmount.toString(),
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
                loanKernel.fillDebtOrder(
                    formatFillDebtOrderParams(
                        orderAddresses,
                        orderValues,
                        termsContractParameters,
                        await Promise.all(
                            tokenIds.map(async (x) => ({
                                ...(await generateLATMintPayload(
                                    loanAssetTokenContract,
                                    defaultLoanAssetTokenValidator,
                                    [x],
                                    [(await loanAssetTokenContract.nonce(x)).toNumber()],
                                    defaultLoanAssetTokenValidator.address
                                )),
                            }))
                        )
                    )
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
                // borrower 1
                borrowerSigner.address,
                // borrower 2
                borrowerSigner.address,
            ];

            const salt = genSalt();
            const riskScore = '1';
            expirationTimestamps = dayjs(new Date()).add(7, 'days').unix();

            const orderValues = [
                CREDITOR_FEE,
                ASSET_PURPOSE_LOAN,
                principalAmount.toString(), // token 1
                principalAmount.toString(), // token 2
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

            await expect(
                loanKernel.fillDebtOrder(
                    formatFillDebtOrderParams(
                        orderAddresses,
                        orderValues,
                        termsContractParameters,
                        await Promise.all(
                            tokenIds.map(async (x) => ({
                                ...(await generateLATMintPayload(
                                    loanAssetTokenContract,
                                    defaultLoanAssetTokenValidator,
                                    [x],
                                    [(await loanAssetTokenContract.nonce(x)).toNumber()],
                                    defaultLoanAssetTokenValidator.address
                                )),
                            }))
                        )
                    )
                )
            ).to.be.revertedWith(`SecuritizationPool: Only Originator can drawdown`);

            await securitizationPoolContract
                .connect(poolCreatorSigner)
                .grantRole(ORIGINATOR_ROLE, untangledAdminSigner.address);

            let stablecoinBalanceOfAdmin = await stableCoin.balanceOf(untangledAdminSigner.address);
            expect(formatEther(stablecoinBalanceOfAdmin)).equal('99000.0');

            await loanKernel.fillDebtOrder(
                formatFillDebtOrderParams(
                    orderAddresses,
                    orderValues,
                    termsContractParameters,
                    await Promise.all(
                        tokenIds.map(async (x) => ({
                            ...(await generateLATMintPayload(
                                loanAssetTokenContract,
                                defaultLoanAssetTokenValidator,
                                [x],
                                [(await loanAssetTokenContract.nonce(x)).toNumber()],
                                defaultLoanAssetTokenValidator.address
                            )),
                        }))
                    )
                )
            );

            const ownerOfAgreement = await loanAssetTokenContract.ownerOf(tokenIds[0]);
            expect(ownerOfAgreement).equal(securitizationPoolContract.address);

            const balanceOfPool = await loanAssetTokenContract.balanceOf(securitizationPoolContract.address);
            expect(balanceOfPool).equal(tokenIds.length);

            stablecoinBalanceOfAdmin = await stableCoin.balanceOf(untangledAdminSigner.address);
            expect(stablecoinBalanceOfAdmin).to.closeTo(parseEther('99019.053'), parseEther('0.01'));
        });
    });

    describe('Loan registry', async () => {
        it('#getLoanDebtor', async () => {
            const result = await loanRegistry.getLoanDebtor(tokenIds[0]);

            expect(result).equal(borrowerSigner.address);
        });

        it('#getLoanTermParams', async () => {
            const result = await loanRegistry.getLoanTermParams(tokenIds[0]);

            expect(result).equal('0x00000000008ac7230489e8000000c35010000000000000000000000f00200000');
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
                loanKernel.concludeLoans(
                    [securitizationPoolContract.address],
                    [tokenIds[0]],
                    loanInterestTermsContract.address
                )
              ).to.be.revertedWith('LoanKernel: Only LoanRepaymentRouter');
        });

        it('only LoanKernel contract can burn', async () => {
            const stablecoinBalanceOfPayerBefore = await stableCoin.balanceOf(untangledAdminSigner.address);
            expect(stablecoinBalanceOfPayerBefore).to.closeTo(parseEther('99019.053'), parseEther('0.01'));

            const stablecoinBalanceOfPoolBefore = await stableCoin.balanceOf(securitizationPoolContract.address);
            expect(stablecoinBalanceOfPoolBefore).to.closeTo(parseEther('180.94'), parseEther('0.01'));

            await loanRepaymentRouter
                .connect(untangledAdminSigner)
                .repayInBatch([tokenIds[0]], [parseEther('100')], stableCoin.address);

            await expect(loanAssetTokenContract.ownerOf(tokenIds[0])).to.be.revertedWith(`ERC721: invalid token ID`);

            const balanceOfPool = await loanAssetTokenContract.balanceOf(securitizationPoolContract.address);
            expect(balanceOfPool).equal(tokenIds.length - 1);

            const stablecoinBalanceOfPayerAfter = await stableCoin.balanceOf(untangledAdminSigner.address);
            expect(stablecoinBalanceOfPoolBefore).to.closeTo(parseEther('180.94'), parseEther('0.01'));

            const stablecoinBalanceOfPoolAfter = await stableCoin.balanceOf(securitizationPoolContract.address);
            expect(stablecoinBalanceOfPoolAfter).to.closeTo(parseEther('190.44'), parseEther('0.01'));
        });

        it('Cannot conclude agreement id again', async () => {
            const signer = await ethers.getSigner(loanRepaymentRouter.address);
            await expect(
            loanKernel.connect(signer).concludeLoans([securitizationPoolContract.address], [tokenIds[0]], loanInterestTermsContract.address)
            ).to.be.revertedWith(`ERC721: invalid token ID`);
        });
    });
});
