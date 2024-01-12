const { ethers, getChainId } = require('hardhat');
const { expect } = require('chai');
const { setup } = require('../setup.js');
const { parseEther, parseUnits, formatEther, formatBytes32String } = ethers.utils;
const dayjs = require('dayjs');
const { time } = require('@nomicfoundation/hardhat-network-helpers');
const { presignedMintMessage, presignedRedeemOrderMessage } = require('../shared/uid-helper');
const { POOL_ADMIN_ROLE, ORIGINATOR_ROLE, BACKEND_ADMIN, SIGNER_ROLE } = require('../constants.js');
const { utils } = require('ethers');
const { getPoolByAddress, unlimitedAllowance } = require('../utils.js');
const { SaleType } = require('../shared/constants.js');
const { getContractAt } = require('@nomiclabs/hardhat-ethers/internal/helpers.js');

/**
 * This file tests the case that a pool invest into another pool
 * */

const ONE_DAY = 86400; // seconds
describe('Pool to Pool', () => {
    // investor pool - the pool which invest into another pool (buy JOT/SOT of another pool)
    describe('Pool A invests in pool B', async () => {
        let stableCoin;
        let securitizationManager;
        let loanKernel;
        let loanRepaymentRouter;
        let loanAssetTokenContract;
        let loanRegistry;
        let uniqueIdentity;
        let registry;
        let noteTokenVault;
        let poolBContract;
        let securitizationPoolValueService;

        // Wallets
        let untangledAdminSigner,
            poolCreatorSigner,
            poolACreator,
            borrowerSigner,
            lenderSigner,
            relayer,
            poolAPot,
            anonymousInvestorSigner,
            backendAdminSigner,
            redeemOrderAdminSigner;

        const stableCoinAmountToBuyJOT = parseEther('1'); // $1
        const stableCoinAmountToBuySOT = parseEther('2'); // $1
        const poolAPotInitialBalance = parseEther('100');
        let poolAContract;
        let mintedNormalTGEPoolBContract;
        let mintedNormalTGEPoolAContract;
        let mintedIncreasingInterestTGEPoolBContract;
        let mintedIncreasingInterestTGEPoolAContract;
        let jotPoolBContract;
        let sotPoolBContract;
        let jotAmount;
        let sotAmount;

        before('init sale', async () => {
            // Init wallets
            [
                untangledAdminSigner,
                poolCreatorSigner,
                poolACreator,
                borrowerSigner,
                lenderSigner,
                relayer,
                poolAPot,
                anonymousInvestorSigner,
                backendAdminSigner,
                redeemOrderAdminSigner,
            ] = await ethers.getSigners();

            // Init contracts
            ({
                stableCoin,
                uniqueIdentity,
                loanAssetTokenContract,
                loanRegistry,
                loanKernel,
                loanRepaymentRouter,
                securitizationManager,
                registry,
                securitizationPoolValueService,
                noteTokenVault,
            } = await setup());

            await noteTokenVault.connect(untangledAdminSigner).grantRole(BACKEND_ADMIN, backendAdminSigner.address);
            await noteTokenVault.connect(untangledAdminSigner).grantRole(SIGNER_ROLE, redeemOrderAdminSigner.address);
            chainId = await getChainId();

            // Create new main pool
            await securitizationManager.grantRole(POOL_ADMIN_ROLE, poolCreatorSigner.address);
            const transaction = await securitizationManager
                .connect(poolCreatorSigner)

                .newPoolInstance(
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

            poolBContract = await getPoolByAddress(securitizationPoolAddress);
            // Init JOT sale
            const jotCap = '10000000000000000000';
            const isLongSaleTGEJOT = true;
            const now = dayjs().unix();
            const initialJOTAmount = parseEther('1');
            const setUpTGEJOTTransaction = await securitizationManager.connect(poolCreatorSigner).setUpTGEForJOT(
                {
                    issuerTokenController: poolCreatorSigner.address,
                    pool: poolBContract.address,
                    minBidAmount: parseEther('1'),
                    saleType: SaleType.NORMAL_SALE,
                    longSale: isLongSaleTGEJOT,
                    ticker: 'Ticker',
                },
                {
                    openingTime: now,
                    closingTime: now + ONE_DAY,
                    rate: 10000,
                    cap: jotCap,
                },
                initialJOTAmount
            );
            const setUpTGEJOTReceipt = await setUpTGEJOTTransaction.wait();
            const [jotTGEAddress] = setUpTGEJOTReceipt.events.find((e) => e.event == 'NewTGECreated').args;
            mintedNormalTGEPoolBContract = await ethers.getContractAt('MintedNormalTGE', jotTGEAddress);

            // Init SOT sale
            const sotCap = '10000000000000000000';
            const isLongSaleTGESOT = true;
            const setUpTGESOTTransaction = await securitizationManager.connect(poolCreatorSigner).setUpTGEForSOT(
                {
                    issuerTokenController: poolCreatorSigner.address,
                    pool: poolBContract.address,
                    minBidAmount: parseEther('1'),
                    saleType: SaleType.MINTED_INCREASING_INTEREST,
                    longSale: isLongSaleTGESOT,
                    ticker: 'Ticker',
                },
                {
                    openingTime: now,
                    closingTime: now + 2 * ONE_DAY,
                    rate: 10000,
                    cap: sotCap,
                },
                {
                    initialInterest: 10000,
                    finalInterest: 90000,
                    timeInterval: 86400,
                    amountChangeEachInterval: 10000,
                }
            );
            const setUpTGESOTReceipt = await setUpTGESOTTransaction.wait();
            const [sotTGEAddress] = setUpTGESOTReceipt.events.find((e) => e.event == 'NewTGECreated').args;
            mintedIncreasingInterestTGEPoolBContract = await ethers.getContractAt(
                'MintedIncreasingInterestTGE',
                sotTGEAddress
            );

            // Create investor pool
            await securitizationManager.grantRole(POOL_ADMIN_ROLE, poolACreator.address);
            const poolACreationTransaction = await securitizationManager
                .connect(poolACreator)

                .newPoolInstance(
                    utils.keccak256(Date.now()),

                    poolACreator.address,
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

            const poolACreationReceipt = await poolACreationTransaction.wait();
            const [poolAContractAddress] = poolACreationReceipt.events.find((e) => e.event == 'NewPoolCreated').args;
            poolAContract = await getPoolByAddress(poolAContractAddress);
            await poolAContract.connect(poolACreator).setPot(poolAPot.address);

            // Init JOT sale PoolA
            const jotCapPoolA = '10000000000000000000';
            const isLongSaleTGEJOTPoolA = true;
            const nowPoolA = dayjs().unix();
            const initialJOTAmountPoolA = parseEther('1');
            const setUpTGEJOTTransactionPoolA = await securitizationManager.connect(poolACreator).setUpTGEForJOT(
                {
                    issuerTokenController: poolACreator.address,
                    pool: poolAContract.address,
                    minBidAmount: parseEther('1'),
                    saleType: SaleType.NORMAL_SALE,
                    longSale: isLongSaleTGEJOTPoolA,
                    ticker: 'Ticker',
                },
                {
                    openingTime: nowPoolA,
                    closingTime: nowPoolA + ONE_DAY,
                    rate: 10000,
                    cap: jotCapPoolA,
                },
                initialJOTAmountPoolA
            );
            const setUpTGEJOTReceiptPoolA = await setUpTGEJOTTransactionPoolA.wait();
            const [jotTGEAddressPoolA] = setUpTGEJOTReceiptPoolA.events.find((e) => e.event == 'NewTGECreated').args;
            mintedNormalTGEPoolAContract = await ethers.getContractAt('MintedNormalTGE', jotTGEAddressPoolA);

            // Init SOT Pool A sale
            const sotCapPoolA = '10000000000000000000';
            const isLongSaleTGESOTPoolA = true;
            const setUpTGESOTTransactionPoolA = await securitizationManager.connect(poolACreator).setUpTGEForSOT(
                {
                    issuerTokenController: poolACreator.address,
                    pool: poolAContract.address,
                    minBidAmount: parseEther('1'),
                    saleType: SaleType.MINTED_INCREASING_INTEREST,
                    longSale: isLongSaleTGESOTPoolA,
                    ticker: 'Ticker',
                },
                {
                    openingTime: now,
                    closingTime: now + 2 * ONE_DAY,
                    rate: 10000,
                    cap: sotCapPoolA,
                },
                {
                    initialInterest: 10000,
                    finalInterest: 90000,
                    timeInterval: 86400,
                    amountChangeEachInterval: 10000,
                }
            );
            const setUpTGESOTReceiptPoolA = await setUpTGESOTTransactionPoolA.wait();
            const [sotTGEAddressPoolA] = setUpTGESOTReceiptPoolA.events.find((e) => e.event == 'NewTGECreated').args;
            mintedIncreasingInterestTGEPoolAContract = await ethers.getContractAt(
                'MintedIncreasingInterestTGE',
                sotTGEAddressPoolA
            );

            // Anonymous investor gain UID
            const SIGNATURE_EXPIRE_TIME = now + ONE_DAY;
            const UID_TYPE_ANONYMOUS_INVESTOR = 0;
            let nonce = 0;
            const ethRequired = parseEther('0.00083');
            const uidMintMessageAnonymousInvestor = presignedMintMessage(
                anonymousInvestorSigner.address,
                UID_TYPE_ANONYMOUS_INVESTOR,
                SIGNATURE_EXPIRE_TIME,
                uniqueIdentity.address,
                nonce,
                chainId
            );
            const signatureForAnonymousInvestor = await untangledAdminSigner.signMessage(
                uidMintMessageAnonymousInvestor
            );
            await uniqueIdentity
                .connect(anonymousInvestorSigner)
                .mint(UID_TYPE_ANONYMOUS_INVESTOR, SIGNATURE_EXPIRE_TIME, signatureForAnonymousInvestor, {
                    value: ethRequired,
                });
            await stableCoin.connect(untangledAdminSigner).transfer(anonymousInvestorSigner.address, parseEther('1'));
            await stableCoin
                .connect(anonymousInvestorSigner)
                .approve(mintedNormalTGEPoolAContract.address, parseEther('1'));
            await securitizationManager
                .connect(anonymousInvestorSigner)
                .buyTokens(mintedNormalTGEPoolAContract.address, parseEther('1'));

            // Pool A pot gain UID
            const UID_TYPE = 0;
            const expiredAt = now + ONE_DAY;
            const uidMintMessage = presignedMintMessage(
                poolAPot.address,
                UID_TYPE,
                expiredAt,
                uniqueIdentity.address,
                nonce,
                chainId
            );
            const signature = await untangledAdminSigner.signMessage(uidMintMessage);
            await uniqueIdentity.connect(poolAPot).mint(UID_TYPE, expiredAt, signature, { value: ethRequired });

            // Faucet stable coin to investorPoolPot
            // await stableCoin.transfer(poolAPot.address, poolAPotInitialBalance); // $100
        });

        it('Pool A pot invests into pool B for JOT', async () => {
            // Invest into main pool (buy JOT token)
            await stableCoin.connect(poolAPot).approve(mintedNormalTGEPoolBContract.address, stableCoinAmountToBuyJOT);
            await securitizationManager
                .connect(poolAPot)
                .buyTokens(mintedNormalTGEPoolBContract.address, stableCoinAmountToBuyJOT);
            expect(await stableCoin.balanceOf(poolAPot.address)).equal('0');
        });
        it('Pool A originator can transfer JOT from pool A pot to pool A', async () => {
            // Transfer to pool
            const jotPoolBAddress = await poolBContract.jotToken();
            jotPoolBContract = await ethers.getContractAt('NoteToken', jotPoolBAddress);
            jotPoolAAmount = await jotPoolBContract.balanceOf(poolAContract.address);

            expect(jotPoolAAmount).equal(parseEther('1'));
        });
        it('Should include B JOT token value in pool A expected assets', async () => {
            // Check values
            const chainTime = await time.latest();
            const expectAssetValue = await securitizationPoolValueService.getExpectedAssetsValue(poolAContract.address);
            expect(expectAssetValue).equal(stableCoinAmountToBuyJOT);
            const tokenERC20AssetAddress = await poolAContract.tokenAssetAddresses(0);
            expect(tokenERC20AssetAddress).equal(jotPoolBContract.address);
        });
        it('Pool A owner can claim B JOT Token from pool A to pool A pot', async () => {
            // Claim back to investor pot wallet
            await poolAContract
                .connect(poolACreator)
                .withdrawERC20Assets([jotPoolBContract.address], [poolAPot.address], [parseEther('1')]);
            const investorPoolPotJotBalance = await jotPoolBContract.balanceOf(poolAPot.address);
            expect(investorPoolPotJotBalance).equal(parseEther('1'));
        });
        it('Pool A pot can make JOT redeem request to pool B', async () => {
            // Redeem
            const investorPoolPotJotBalance = await jotPoolBContract.balanceOf(poolAPot.address);
            await jotPoolBContract.connect(poolAPot).approve(noteTokenVault.address, unlimitedAllowance);

            const redeemParam = {
                pool: poolBContract.address,
                noteTokenAddress: jotPoolBContract.address,
                noteTokenRedeemAmount: parseEther('1'),
            };
            const redeemOrderMessage = presignedRedeemOrderMessage(
                poolAPot.address,
                redeemParam.pool,
                redeemParam.noteTokenAddress,
                redeemParam.noteTokenRedeemAmount,
                chainId
            );
            const redeemSignature = await redeemOrderAdminSigner.signMessage(redeemOrderMessage);

            await noteTokenVault.connect(poolAPot).redeemOrder(redeemParam, redeemSignature);

            await noteTokenVault
                .connect(backendAdminSigner)
                .preDistribute(poolBContract.address, parseEther('1'), [jotPoolBContract.address], [parseEther('1')]);
            await noteTokenVault
                .connect(backendAdminSigner)
                .disburseAll(
                    poolBContract.address,
                    jotPoolBContract.address,
                    [poolAPot.address],
                    [parseEther('1')],
                    [parseEther('1')]
                );

            const investorPoolPotJotBalanceAfterRedeem = await jotPoolBContract.balanceOf(poolAPot.address);
            const investorPoolPotStableCoinBalanceAfterRedeem = await stableCoin.balanceOf(poolAPot.address);
            expect(investorPoolPotStableCoinBalanceAfterRedeem).equal(parseEther('1'));
            expect(investorPoolPotJotBalanceAfterRedeem).equal('0');
        });

        it('Pool A pot invests into pool B for SOT', async () => {
            await stableCoin.connect(untangledAdminSigner).transfer(anonymousInvestorSigner.address, parseEther('2'));
            await stableCoin
                .connect(anonymousInvestorSigner)
                .approve(mintedNormalTGEPoolAContract.address, parseEther('2'));
            await securitizationManager
                .connect(anonymousInvestorSigner)
                .buyTokens(mintedNormalTGEPoolAContract.address, parseEther('2'));
            // Invest into main pool (buy JOT token)
            await stableCoin.connect(poolAPot).approve(mintedNormalTGEPoolBContract.address, stableCoinAmountToBuyJOT);
            await securitizationManager
                .connect(poolAPot)
                .buyTokens(mintedNormalTGEPoolBContract.address, stableCoinAmountToBuyJOT);
            const value = await mintedIncreasingInterestTGEPoolBContract.hasStarted();
            // Invest into main pool (buy SOT token)
            await stableCoin
                .connect(poolAPot)
                .approve(mintedIncreasingInterestTGEPoolBContract.address, stableCoinAmountToBuySOT);
            await securitizationManager
                .connect(poolAPot)
                .buyTokens(mintedIncreasingInterestTGEPoolBContract.address, stableCoinAmountToBuySOT);
            expect(await stableCoin.balanceOf(poolAPot.address)).equal('0');
        });
        it('Pool A originator can transfer SOT from pool A pot to pool A', async () => {
            // Transfer to pool
            const sotPoolBAddress = await poolBContract.sotToken();
            sotPoolBContract = await ethers.getContractAt('NoteToken', sotPoolBAddress);
            sotPoolAContractAmount = await sotPoolBContract.balanceOf(poolAContract.address);

            expect(sotPoolAContractAmount).equal(parseEther('2'));
        });
        it('Should include B SOT token value in pool A expected assets', async () => {
            // Check values
            const chainTime = await time.latest();
            const expectAssetValue = await securitizationPoolValueService.getExpectedAssetsValue(poolAContract.address);
            expect(expectAssetValue).equal(parseEther('3'));
            const tokenERC20AssetAddress = await poolAContract.tokenAssetAddresses(1);
            expect(tokenERC20AssetAddress).equal(sotPoolBContract.address);
        });
        it('Pool A owner can claim B SOT Token from pool A to pool A pot', async () => {
            // Claim back to investor pot wallet
            await poolAContract
                .connect(poolACreator)
                .withdrawERC20Assets([sotPoolBContract.address], [poolAPot.address], [parseEther('2')]);
            const investorPoolPotJotBalance = await sotPoolBContract.balanceOf(poolAPot.address);
            expect(investorPoolPotJotBalance).equal(parseEther('2'));
        });
        it('Pool A pot can make SOT redeem request to pool B', async () => {
            // Redeem
            const investorPoolPotSotBalance = await sotPoolBContract.balanceOf(poolAPot.address);

            await sotPoolBContract.connect(poolAPot).approve(noteTokenVault.address, unlimitedAllowance);

            const redeemParam = {
                pool: poolBContract.address,
                noteTokenAddress: sotPoolBContract.address,
                noteTokenRedeemAmount: investorPoolPotSotBalance,
            };
            const redeemOrderMessage = presignedRedeemOrderMessage(
                poolAPot.address,
                redeemParam.pool,
                redeemParam.noteTokenAddress,
                redeemParam.noteTokenRedeemAmount,
                chainId
            );
            const redeemSignature = await redeemOrderAdminSigner.signMessage(redeemOrderMessage);

            await noteTokenVault.connect(poolAPot).redeemOrder(redeemParam, redeemSignature);

            await noteTokenVault
                .connect(backendAdminSigner)
                .preDistribute(
                    poolBContract.address,
                    investorPoolPotSotBalance,
                    [sotPoolBContract.address],
                    [parseEther('2')]
                );
            await noteTokenVault
                .connect(backendAdminSigner)
                .disburseAll(
                    poolBContract.address,
                    sotPoolBContract.address,
                    [poolAPot.address],
                    [investorPoolPotSotBalance],
                    [parseEther('2')]
                );

            const investorPoolPotJotBalanceAfterRedeem = await sotPoolBContract.balanceOf(poolAPot.address);
            const investorPoolPotStableCoinBalanceAfterRedeem = await stableCoin.balanceOf(poolAPot.address);
            expect(investorPoolPotStableCoinBalanceAfterRedeem).equal(stableCoinAmountToBuySOT);
            expect(investorPoolPotJotBalanceAfterRedeem).equal('0');
        });
    });

    describe('Pool A invests in pool B, pool B invests in pool C', async () => {
        let stableCoin;
        let securitizationManager;
        let loanKernel;
        let loanRepaymentRouter;
        let loanAssetTokenContract;
        let loanRegistry;
        let uniqueIdentity;
        let registry;
        let noteTokenVault;
        let distributionAssessor;
        let securitizationPoolValueService;
        let chainId;

        let poolAContract;
        let poolBContract;
        let poolCContract;
        let mintedNormalTGEPoolAContract;
        let mintedIncreasingInterestTGEPoolAContract;
        let mintedNormalTGEPoolBContract;
        let mintedIncreasingInterestTGEPoolBContract;
        let mintedNormalTGEPoolCContract;
        let mintedIncreasingInterestTGEPoolCContract;
        let sotBContract;
        let sotCContract;
        let jotBContract;
        let jotCContract;
        let sotAmountABuyFromB; // Currency amount
        let sotAmountBBuyFromC; // Currency amount

        // Wallets
        let untangledAdminSigner,
            poolBCreatorSigner,
            poolACreatorSigner,
            poolCCreatorSigner,
            poolAOriginatorSigner,
            poolBOriginatorSigner,
            lenderSigner,
            relayer,
            poolAPotSigner,
            poolBPotSigner,
            poolCPotSigner,
            anonymousInvestorSigner,
            backendAdminSigner,
            redeemOrderAdminSigner;

        const stableCoinAmountToBuyBJOT = parseEther('2'); // $2
        const stableCoinAmountToBuyCJOT = parseEther('1'); // $1
        const poolAPotInitialBalance = parseEther('100');
        const expectSOTAmountABuyFromB = parseEther('2');
        const expectSOTAmountBBuyFromC = parseEther('1');
        const NOW = dayjs().unix();
        before('init sale', async () => {
            // Init wallets
            [
                untangledAdminSigner,
                poolBCreatorSigner,
                poolACreatorSigner,
                poolCCreatorSigner,
                poolAOriginatorSigner,
                poolBOriginatorSigner,
                lenderSigner,
                relayer,
                poolAPotSigner,
                poolBPotSigner,
                poolCPotSigner,
                anonymousInvestorSigner,
                backendAdminSigner,
                redeemOrderAdminSigner,
            ] = await ethers.getSigners();

            // Init contracts
            ({
                stableCoin,
                uniqueIdentity,
                loanAssetTokenContract,
                loanRegistry,
                loanKernel,
                loanRepaymentRouter,
                securitizationManager,
                distributionAssessor,
                registry,
                securitizationPoolValueService,
                noteTokenVault,
            } = await setup());

            await noteTokenVault.connect(untangledAdminSigner).grantRole(BACKEND_ADMIN, backendAdminSigner.address);
            await noteTokenVault.connect(untangledAdminSigner).grantRole(SIGNER_ROLE, redeemOrderAdminSigner.address);
            chainId = await getChainId();

            // Create pool C
            await securitizationManager.grantRole(POOL_ADMIN_ROLE, poolCCreatorSigner.address);
            const poolCCreationTransaction = await securitizationManager
                .connect(poolCCreatorSigner)

                .newPoolInstance(
                    utils.keccak256(Date.now()),

                    poolCCreatorSigner.address,
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

            const poolCCreationReceipt = await poolCCreationTransaction.wait();
            const [poolCContractAddress] = poolCCreationReceipt.events.find((e) => e.event == 'NewPoolCreated').args;
            poolCContract = await getPoolByAddress(poolCContractAddress);

            // Set pot for pool C
            await poolCContract.connect(poolCCreatorSigner).setPot(poolCPotSigner.address);
            await stableCoin.connect(poolCPotSigner).approve(poolCContract.address, ethers.constants.MaxUint256);

            // Init JOT sale pool C
            const jotCapPoolC = '10000000000000000000';
            const isLongSaleTGEJOTPoolC = true;
            const initialJOTAmountPoolC = parseEther('1');
            const setUpTGEJOTTransactionPoolC = await securitizationManager.connect(poolCCreatorSigner).setUpTGEForJOT(
                {
                    issuerTokenController: poolCCreatorSigner.address,
                    pool: poolCContract.address,
                    minBidAmount: parseEther('1'),
                    saleType: SaleType.NORMAL_SALE,
                    longSale: isLongSaleTGEJOTPoolC,
                    ticker: 'Ticker',
                },
                {
                    openingTime: NOW,
                    closingTime: NOW + ONE_DAY,
                    rate: 10000,
                    cap: jotCapPoolC,
                },
                initialJOTAmountPoolC
            );
            const setUpTGEJOTPoolCReceipt = await setUpTGEJOTTransactionPoolC.wait();
            const [jotTGEPoolCAddress] = setUpTGEJOTPoolCReceipt.events.find((e) => e.event == 'NewTGECreated').args;
            mintedNormalTGEPoolCContract = await ethers.getContractAt('MintedNormalTGE', jotTGEPoolCAddress);
            const jotPoolCAddress = await poolCContract.jotToken();
            jotCContract = await ethers.getContractAt('NoteToken', jotPoolCAddress);

            // Init SOT sale pool C
            const sotCapPoolC = '10000000000000000000';
            const isLongSaleTGESOTPoolC = true;
            const setUpTGESOTTransactionPoolC = await securitizationManager.connect(poolCCreatorSigner).setUpTGEForSOT(
                {
                    issuerTokenController: poolCCreatorSigner.address,
                    pool: poolCContract.address,
                    minBidAmount: parseEther('1'),
                    saleType: SaleType.MINTED_INCREASING_INTEREST,
                    longSale: isLongSaleTGESOTPoolC,
                    ticker: 'Ticker',
                },
                {
                    openingTime: NOW,
                    closingTime: NOW + 2 * ONE_DAY,
                    rate: 10000,
                    cap: sotCapPoolC,
                },
                {
                    initialInterest: 10000,
                    finalInterest: 90000,
                    timeInterval: 86400,
                    amountChangeEachInterval: 10000,
                }
            );
            const setUpTGESOTPoolCReceipt = await setUpTGESOTTransactionPoolC.wait();
            const [sotTGEPoolCAddress] = setUpTGESOTPoolCReceipt.events.find((e) => e.event == 'NewTGECreated').args;
            mintedIncreasingInterestTGEPoolCContract = await ethers.getContractAt(
                'MintedIncreasingInterestTGE',
                sotTGEPoolCAddress
            );
            const sotPoolCAddress = await poolCContract.sotToken();
            sotCContract = await ethers.getContractAt('NoteToken', sotPoolCAddress);

            // Create pool B
            await securitizationManager.grantRole(POOL_ADMIN_ROLE, poolBCreatorSigner.address);
            const transaction = await securitizationManager
                .connect(poolBCreatorSigner)

                .newPoolInstance(
                    utils.keccak256(Date.now()),

                    poolBCreatorSigner.address,
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

            // Set pot for pool B
            poolBContract = await getPoolByAddress(securitizationPoolAddress);
            await poolBContract.connect(poolBCreatorSigner).setPot(poolBPotSigner.address);
            await stableCoin.connect(poolBPotSigner).approve(poolBContract.address, ethers.constants.MaxUint256);

            // Init JOT sale pool B
            const jotCapPoolB = '10000000000000000000';
            const isLongSaleTGEJOTPoolB = true;
            const initialJOTAmountPoolB = parseEther('1');
            const setUpTGEJOTTransactionPoolB = await securitizationManager.connect(poolBCreatorSigner).setUpTGEForJOT(
                {
                    issuerTokenController: poolBCreatorSigner.address,
                    pool: poolBContract.address,
                    minBidAmount: parseEther('1'),
                    saleType: SaleType.NORMAL_SALE,
                    longSale: isLongSaleTGEJOTPoolB,
                    ticker: 'Ticker',
                },
                {
                    openingTime: NOW,
                    closingTime: NOW + ONE_DAY,
                    rate: 10000,
                    cap: jotCapPoolB,
                },
                initialJOTAmountPoolB
            );
            const setUpTGEJOTPoolBReceipt = await setUpTGEJOTTransactionPoolB.wait();
            const [jotTGEPoolBAddress] = setUpTGEJOTPoolBReceipt.events.find((e) => e.event == 'NewTGECreated').args;
            mintedNormalTGEPoolBContract = await ethers.getContractAt('MintedNormalTGE', jotTGEPoolBAddress);
            const jotPoolBAddress = await poolBContract.jotToken();
            jotBContract = await ethers.getContractAt('NoteToken', jotPoolBAddress);

            // Init SOT sale pool B
            const sotCapPoolB = '10000000000000000000';
            const isLongSaleTGESOTPoolB = true;
            const setUpTGESOTTransactionPoolB = await securitizationManager.connect(poolBCreatorSigner).setUpTGEForSOT(
                {
                    issuerTokenController: poolBCreatorSigner.address,
                    pool: poolBContract.address,
                    minBidAmount: parseEther('1'),
                    saleType: SaleType.MINTED_INCREASING_INTEREST,
                    longSale: isLongSaleTGESOTPoolB,
                    ticker: 'Ticker',
                },
                {
                    openingTime: NOW,
                    closingTime: NOW + 2 * ONE_DAY,
                    rate: 10000,
                    cap: sotCapPoolB,
                },
                {
                    initialInterest: 10000,
                    finalInterest: 90000,
                    timeInterval: 86400,
                    amountChangeEachInterval: 10000,
                }
            );
            const setUpTGESOTPoolBReceipt = await setUpTGESOTTransactionPoolB.wait();
            const [sotTGEPoolBAddress] = setUpTGESOTPoolBReceipt.events.find((e) => e.event == 'NewTGECreated').args;
            mintedIncreasingInterestTGEPoolBContract = await ethers.getContractAt(
                'MintedIncreasingInterestTGE',
                sotTGEPoolBAddress
            );
            const sotPoolBAddress = await poolBContract.sotToken();
            sotBContract = await ethers.getContractAt('NoteToken', sotPoolBAddress);

            // Create pool A
            await securitizationManager.grantRole(POOL_ADMIN_ROLE, poolACreatorSigner.address);
            const poolACreationTransaction = await securitizationManager
                .connect(poolACreatorSigner)

                .newPoolInstance(
                    utils.keccak256(Date.now()),

                    poolACreatorSigner.address,
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

            const poolACreationReceipt = await poolACreationTransaction.wait();
            const [poolAContractAddress] = poolACreationReceipt.events.find((e) => e.event == 'NewPoolCreated').args;
            poolAContract = await getPoolByAddress(poolAContractAddress);
            await poolAContract.connect(poolACreatorSigner).setPot(poolAPotSigner.address);

            // Init JOT sale PoolA
            const jotCapPoolA = '10000000000000000000';
            const isLongSaleTGEJOTPoolA = true;
            const initialJOTAmountPoolA = parseEther('1');
            const setUpTGEJOTTransactionPoolA = await securitizationManager.connect(poolACreatorSigner).setUpTGEForJOT(
                {
                    issuerTokenController: poolACreatorSigner.address,
                    pool: poolAContract.address,
                    minBidAmount: parseEther('1'),
                    saleType: SaleType.NORMAL_SALE,
                    longSale: isLongSaleTGEJOTPoolA,
                    ticker: 'Ticker',
                },
                {
                    openingTime: NOW,
                    closingTime: NOW + ONE_DAY,
                    rate: 10000,
                    cap: jotCapPoolA,
                },
                initialJOTAmountPoolA
            );
            const setUpTGEJOTReceiptPoolA = await setUpTGEJOTTransactionPoolA.wait();
            const [jotTGEAddressPoolA] = setUpTGEJOTReceiptPoolA.events.find((e) => e.event == 'NewTGECreated').args;
            mintedNormalTGEPoolAContract = await ethers.getContractAt('MintedNormalTGE', jotTGEAddressPoolA);

            // Init SOT Pool A sale
            const sotCapPoolA = '10000000000000000000';
            const isLongSaleTGESOTPoolA = true;
            const setUpTGESOTTransactionPoolA = await securitizationManager.connect(poolACreatorSigner).setUpTGEForSOT(
                {
                    issuerTokenController: poolACreatorSigner.address,
                    pool: poolAContract.address,
                    minBidAmount: parseEther('1'),
                    saleType: SaleType.MINTED_INCREASING_INTEREST,
                    longSale: isLongSaleTGESOTPoolA,
                    ticker: 'Ticker',
                },
                {
                    openingTime: NOW,
                    closingTime: NOW + 2 * ONE_DAY,
                    rate: 10000,
                    cap: sotCapPoolA,
                },
                {
                    initialInterest: 10000,
                    finalInterest: 90000,
                    timeInterval: 86400,
                    amountChangeEachInterval: 10000,
                }
            );

            // Anonymous investor gain UID
            const UID_TYPE_ANONYMOUS_INVESTOR = 0;
            const SIGNATURE_EXPIRE_TIME = NOW + ONE_DAY;
            const ethRequired = parseEther('0.00083');
            const uidMintMessageAnonymousInvestor = presignedMintMessage(
                anonymousInvestorSigner.address,
                UID_TYPE_ANONYMOUS_INVESTOR,
                SIGNATURE_EXPIRE_TIME,
                uniqueIdentity.address,
                0,
                chainId
            );
            const signatureForAnonymousInvestor = await untangledAdminSigner.signMessage(
                uidMintMessageAnonymousInvestor
            );
            await uniqueIdentity
                .connect(anonymousInvestorSigner)
                .mint(UID_TYPE_ANONYMOUS_INVESTOR, SIGNATURE_EXPIRE_TIME, signatureForAnonymousInvestor, {
                    value: ethRequired,
                });
            await stableCoin.connect(untangledAdminSigner).transfer(anonymousInvestorSigner.address, parseEther('2'));
            await stableCoin
                .connect(anonymousInvestorSigner)
                .approve(mintedNormalTGEPoolAContract.address, parseEther('2'));
            await securitizationManager
                .connect(anonymousInvestorSigner)
                .buyTokens(mintedNormalTGEPoolAContract.address, parseEther('2'));

            // Pool A pot gain UID
            const UID_TYPE = 0;
            const nonce = 0;
            const uidMintMessagePotA = presignedMintMessage(
                poolAPotSigner.address,
                UID_TYPE,
                SIGNATURE_EXPIRE_TIME,
                uniqueIdentity.address,
                nonce,
                chainId
            );
            const signaturePotA = await untangledAdminSigner.signMessage(uidMintMessagePotA);
            await uniqueIdentity
                .connect(poolAPotSigner)
                .mint(UID_TYPE, SIGNATURE_EXPIRE_TIME, signaturePotA, { value: ethRequired });

            // Pool B pot gain UID
            const uidMintMessagePotB = presignedMintMessage(
                poolBPotSigner.address,
                UID_TYPE,
                SIGNATURE_EXPIRE_TIME,
                uniqueIdentity.address,
                nonce,
                chainId
            );
            const signaturePotB = await untangledAdminSigner.signMessage(uidMintMessagePotB);
            await uniqueIdentity
                .connect(poolBPotSigner)
                .mint(UID_TYPE, SIGNATURE_EXPIRE_TIME, signaturePotB, { value: ethRequired });

            // Faucet stable coin to investorPoolPot
            // await stableCoin.transfer(poolAPotSigner.address, poolAPotInitialBalance); // $100
        });

        it('Pool A pot invests into pool B for JOT', async () => {
            // Invest into main pool (buy JOT token)
            await stableCoin
                .connect(poolAPotSigner)
                .approve(mintedNormalTGEPoolBContract.address, stableCoinAmountToBuyBJOT);
            await securitizationManager
                .connect(poolAPotSigner)
                .buyTokens(mintedNormalTGEPoolBContract.address, stableCoinAmountToBuyBJOT);
            expect(await stableCoin.balanceOf(poolAPotSigner.address)).equal('0');
            expect(await jotBContract.balanceOf(poolAContract.address)).equal(parseEther('2'));
        });
        it('Pool B pot invests into pool C for JOT', async () => {
            await stableCoin
                .connect(poolBPotSigner)
                .approve(mintedNormalTGEPoolCContract.address, stableCoinAmountToBuyCJOT);
            await securitizationManager
                .connect(poolBPotSigner)
                .buyTokens(mintedNormalTGEPoolCContract.address, stableCoinAmountToBuyCJOT);
            expect(await stableCoin.balanceOf(poolBPotSigner.address)).equal(
                stableCoinAmountToBuyBJOT.sub(stableCoinAmountToBuyCJOT)
            );
            expect(await jotCContract.balanceOf(poolBContract.address)).equal(parseEther('1'));
        });
        it('Pool A originator can transfer B-JOT from pool A pot to pool A', async () => {
            expect(await jotBContract.balanceOf(poolAContract.address)).equal(parseEther('2'));
        });
        it('Pool B originator can transfer C-JOT from pool B pot to pool B', async () => {
            expect(await jotCContract.balanceOf(poolBContract.address)).equal(parseEther('1'));
        });
        it('Should include B-JOT token value in pool A expected assets', async () => {
            // Check values
            const tokenERC20AssetLength = await poolAContract.getTokenAssetAddressesLength();
            const balanceOfPoolAWithjotBContract = await jotBContract.balanceOf(poolAContract.address);

            const expectAssetValue = await securitizationPoolValueService.getExpectedAssetsValue(poolAContract.address);
            expect(expectAssetValue).closeTo(parseEther('2'), parseEther('0.01'));
            // SOT address was added to tokenAssetAddresses variables
            const tokenERC20AssetAddress = await poolAContract.tokenAssetAddresses(0);
            expect(tokenERC20AssetAddress).equal(jotBContract.address);
        });
        it('Should include C-JOT token value in pool B expected assets', async () => {
            // Check values
            const chainTime = await time.latest();
            // SOT address was added to tokenAssetAddresses variables
            const tokenERC20AssetAddress = await poolBContract.tokenAssetAddresses(0);
            expect(tokenERC20AssetAddress).equal(jotCContract.address);
            const expectAssetValue = await securitizationPoolValueService.getExpectedAssetsValue(poolBContract.address);
            expect(expectAssetValue).equal(stableCoinAmountToBuyCJOT);
        });
        it('Pool A owner can claim B-JOT Token from pool A to pool A pot', async () => {
            // Claim back to investor pot wallet
            await poolAContract
                .connect(poolACreatorSigner)
                .withdrawERC20Assets([jotBContract.address], [poolAPotSigner.address], [parseEther('2')]);
            const sotBalance = await jotBContract.balanceOf(poolAPotSigner.address);
            expect(sotBalance).equal(expectSOTAmountABuyFromB);
        });
        it('Pool B owner can claim C-JOT Token from pool B to pool B pot', async () => {
            // Claim back to investor pot wallet
            await poolBContract
                .connect(poolBCreatorSigner)
                .withdrawERC20Assets([jotCContract.address], [poolBPotSigner.address], [parseEther('1')]);
            const sotBalance = await jotCContract.balanceOf(poolBPotSigner.address);
            expect(sotBalance).equal(expectSOTAmountBBuyFromC);
        });
        it('Pool B pot can make JOT redeem request to pool C', async () => {
            // Redeem
            const jotBalance = await jotCContract.balanceOf(poolBPotSigner.address);

            await jotCContract.connect(poolBPotSigner).approve(noteTokenVault.address, unlimitedAllowance);

            const redeemParam = {
                pool: poolCContract.address,
                noteTokenAddress: jotCContract.address,
                noteTokenRedeemAmount: jotBalance,
            };
            const redeemOrderMessage = presignedRedeemOrderMessage(
                poolBPotSigner.address,
                redeemParam.pool,
                redeemParam.noteTokenAddress,
                redeemParam.noteTokenRedeemAmount,
                chainId
            );
            const redeemSignature = await redeemOrderAdminSigner.signMessage(redeemOrderMessage);

            await noteTokenVault.connect(poolBPotSigner).redeemOrder(redeemParam, redeemSignature);

            await noteTokenVault
                .connect(backendAdminSigner)
                .preDistribute(
                    poolCContract.address,
                    stableCoinAmountToBuyCJOT,
                    [jotCContract.address],
                    [parseEther('1')]
                );
            await noteTokenVault
                .connect(backendAdminSigner)
                .disburseAll(
                    poolCContract.address,
                    jotCContract.address,
                    [poolBPotSigner.address],
                    [stableCoinAmountToBuyCJOT],
                    [parseEther('1')]
                );
            const investorPoolPotJotBalanceAfterRedeem = await jotCContract.balanceOf(poolBPotSigner.address);
            const investorPoolPotStableCoinBalanceAfterRedeem = await stableCoin.balanceOf(poolBPotSigner.address);
            expect(investorPoolPotStableCoinBalanceAfterRedeem).equal(stableCoinAmountToBuyBJOT);
            expect(investorPoolPotJotBalanceAfterRedeem).equal('0');
        });

        it('Pool A pot can make JOT redeem request to pool B', async () => {
            // Redeem
            const investorPoolPotJotBalance = await jotBContract.balanceOf(poolAPotSigner.address);

            await jotBContract.connect(poolAPotSigner).approve(noteTokenVault.address, unlimitedAllowance);

            const redeemParam = {
                pool: poolBContract.address,
                noteTokenAddress: jotBContract.address,
                noteTokenRedeemAmount: investorPoolPotJotBalance,
            };
            const redeemOrderMessage = presignedRedeemOrderMessage(
                poolAPotSigner.address,
                redeemParam.pool,
                redeemParam.noteTokenAddress,
                redeemParam.noteTokenRedeemAmount,
                chainId
            );
            const redeemSignature = await redeemOrderAdminSigner.signMessage(redeemOrderMessage);

            await noteTokenVault.connect(poolAPotSigner).redeemOrder(redeemParam, redeemSignature);

            await noteTokenVault
                .connect(backendAdminSigner)
                .preDistribute(
                    poolBContract.address,
                    stableCoinAmountToBuyBJOT,
                    [jotBContract.address],
                    [parseEther('2')]
                );
            await noteTokenVault
                .connect(backendAdminSigner)
                .disburseAll(
                    poolBContract.address,
                    jotBContract.address,
                    [poolAPotSigner.address],
                    [stableCoinAmountToBuyBJOT],
                    [parseEther('2')]
                );

            const investorPoolPotJotBalanceAfterRedeem = await jotBContract.balanceOf(poolAPotSigner.address);
            const investorPoolPotStableCoinBalanceAfterRedeem = await stableCoin.balanceOf(poolAPotSigner.address);
            expect(investorPoolPotStableCoinBalanceAfterRedeem).closeTo(stableCoinAmountToBuyBJOT, parseEther('0.01'));
            expect(investorPoolPotJotBalanceAfterRedeem).equal('0');
        });
    });
});
