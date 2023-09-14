// const {expectRevert} = require('@openzeppelin/test-helpers');
// const { assert } = require('chai');
// const { assembleFiles } = require('solidity-coverage/plugins/resources/plugin.utils');
// const Registry = artifacts.require("Registry");
// const SecuritizationPool = artifacts.require("SecuritizationPool");
// const SecuritizationManager = artifacts.require("SecuritizationManager");
// const LoanKernel = artifacts.require("LoanKernel");

// const NoteToken = artifacts.require("NoteToken");
// const NoteTokenFactory = artifacts.require("NoteTokenFactory");
// const LoanAssetToken = artifacts.require("LoanAssetToken");
// const MintedIncreasingInterestTGE = artifacts.require("MintedIncreasingInterestTGE");
// const TokenGenerationEventFactory = artifacts.require("TokenGenerationEventFactory");
// // MintedNormalTGE
// contract('SecuritizationManager', (accounts) => {
//     let smContract;
//     let registry
//     let smAddress;
//     let registryAddress;
//     let securitizationPool
//     let myToken;
//     let loanAssetToken;
//     let loanKernel
//     let noteToken;
//     let noteTokenFactory;
//     let mintedIncreasingInterestTGE;
//     let tokenGenerationEventFactory;
//     let registryInitialize
//     let addressPool;
//     let ADMIN_ROLE;
//     let OWNER_ROLE;
//     let myTokenAddress;
//     let poolToSOT
//     let poolToJOT
//     var BN = web3.utils.BN;
//     var tgeSOT;
//     var tgeJOT;
//     var minFirstLossCushion
//     var tgeAddress
//     let newPool
//     before(async () => {
//         registry = await Registry.new();

//         tokenGenerationEventFactory = await TokenGenerationEventFactory.new();
//         // in protocol/fab
//         mintedIncreasingInterestTGE = await MintedIncreasingInterestTGE.new();
//         // in fab
//         loanAssetToken = await LoanAssetToken.new();
//         // in tokens/erc721

//         loanKernel = await LoanKernel.new();
//         // in loan
//         securitizationPool = await SecuritizationPool.new();
//         // protocol/pool
//         noteToken = await NoteToken.new("Test","TST", 18, securitizationPool.address,1);
//         myTokenAddress = noteToken.address;
//         smContract = await SecuritizationManager.new();
//         // protocol/pool
//         noteTokenFactory = await NoteTokenFactory.new()
//         // protocol/pool
//         smAddress = smContract.address;
//         console.log(18, smAddress);

//         registryAddress = registry.address;

//     })

//     it('Should deploy SecuritizationManager contract properly', async () => {
//         assert.notEqual(smAddress, 0x0);
//         assert.notEqual(smAddress, '');
//         assert.notEqual(smAddress, null);
//         assert.notEqual(smAddress, undefined);

//     });
//     it('should initialize succesful ', async () => {
//         await smContract.initialize(registryAddress);
//          registryInitialize = await smContract.registry();
//         assert.equal(registryAddress, registryInitialize, "succesful initialize Registry");

//     })
//     it('should grant Role succesful ', async () => {
//         let CREATOR_POOL = await smContract.POOL_CREATOR();
//         await smContract.grantRole(CREATOR_POOL, accounts[0]);
//         let role = await smContract.hasRole(CREATOR_POOL, accounts[0]);
//         assert.equal(true, role, "succesful grant Role creator Pool for admin");
//     })

//     it('create new pool succesful', async () => {
//         console.log(42, accounts[0])
//          OWNER_ROLE = await registry.OWNER_ROLE();
//         ADMIN_ROLE = await registry.DEFAULT_ADMIN_ROLE();
//         console.log(45, OWNER_ROLE, accounts[0]);
//         await registry.initialize();
//         await registry.setMintedIncreasingInterestTGE(mintedIncreasingInterestTGE.address);
//         await registry.setNoteTokenFactory(noteTokenFactory.address);
//         await registry.setTokenGenerationEventFactory(tokenGenerationEventFactory.address);
//         await tokenGenerationEventFactory.initialize(registryAddress);
//         await tokenGenerationEventFactory.grantRole(ADMIN_ROLE,accounts[0])
//         await noteTokenFactory.initialize(registryAddress);
//         await noteTokenFactory.grantRole(ADMIN_ROLE, accounts[0]);
//         await loanKernel.initialize(registryAddress);
//         await loanKernel.grantRole(ADMIN_ROLE, accounts[0]);
//         await loanAssetToken.initialize(registryAddress,"TEST", "TST", "test.com" );
//         await registry.grantRole(ADMIN_ROLE, accounts[0], {from:accounts[0]})
//         await registry.setSecuritizationManager(smAddress);
//         let securitizationPoolAddress = securitizationPool.address;
//         await registry.setSecuritizationPool(securitizationPoolAddress)
//         let loanAssetTokenAddress = loanAssetToken.address
//         await registry.setLoanAssetToken(loanAssetTokenAddress);
//         let loanKernelAddress = loanKernel.address
//         await registry.setLoanKernel(loanKernelAddress);

//         minFirstLossCushion= 120000;
//         await securitizationPool.initialize(registryAddress, myTokenAddress,minFirstLossCushion);
//         await smContract.grantRole(ADMIN_ROLE, accounts[0])
//         const transaction = await smContract.newPoolInstance(myTokenAddress, minFirstLossCushion);
//         let arrReceiptLogs = []
//         arrReceiptLogs.push(transaction.receipt.logs)

//         let logs = transaction.logs

//          addressPool = logs[7]['args'][0]
//         console.log(90,addressPool)
//         // console.log(78, transaction.receipt.logs, )
//         let isPool = await smContract.isExistingPools(addressPool);
//         console.log(80, isPool)
//         assert.equal(true, isPool, "succesful creae new Pool instance");

//         let poolExist = await smContract.isExistingPools(addressPool);
//         console.log(124, poolExist);
//         assert.equal(true, poolExist, "succesful create new  Pool Instance");
//     });

//     it('initialie SOT successful', async () => {
//         let txSOT = await smContract.initialTGEForSOT(
//             accounts[0],
//             addressPool,
//             [0,
//             18],
//             true,
//             "SOT Test"
//         )
//         // console.log(136, txSOT)
//         tgeSOT = txSOT.logs[10].args.instanceAddress
//         console.log(137,tgeSOT)
//         poolToSOT = await smContract.poolToSOT(addressPool);
//         console.log(138, poolToSOT)
//         assert.notEqual(poolToSOT, 0x0, "Fail on creating SOT");
//     })

//     it(' should initialize succesful TGE for JOT ', async () => {

//         let txJOT = await smContract.initialTGEForJOT(
//             accounts[0],
//             addressPool,
//             [0,
//             18],
//             true,
//             "JOT TOKEN"
//         )
//         // console.log(154, txJOT)
//         tgeJOT = txJOT.logs[10].args.instanceAddress
//         console.log(155, tgeJOT)
//          poolToJOT = await smContract.poolToJOT(addressPool);
//         console.log(152, poolToJOT)
//         assert.notEqual(poolToJOT, 0x0, "Fail on creating JOT");
//     })

//     // need to create a new pool and call set up tge for sot
//     it(' Should set up TGE  successfully ', async () => {
//         let openingTime = 1689590489;

//         let closingTime =1697539289 ;
//         let rate =2 ;
//         let cap = Math.pow(10,18);
//         console.log(162, cap )
//         cap = cap.toString();
//         const transaction = await smContract.newPoolInstance(myTokenAddress, minFirstLossCushion);
//         let logs = transaction.logs

//          newPool =  logs[7]['args'][0]

//         const txSetup1 = await smContract.setUpTGEForSOT(
//             accounts[2],
//             newPool,
//             [0, 18],
//             true,
//             cap,
//             100000,
//             100000,
//             86400,
//             0,
//             { "openingTime": openingTime,   "closingTime": closingTime,"rate": rate,"cap": cap },
//             "SOT"
//         )
//         tgeAddress = txSetup1.logs[10].args.instanceAddress;
//         console.log(223, tgeAddress)
//         let checkTGE = await smContract.isExistingTGEs(tgeAddress);
//         console.log(225, checkTGE)
//         assert.equal(checkTGE, true, "Fail on setup TGE")
//     })

//     it(' Should buy token successfully ', async () => {
//         let amountBuy = "100000000000000000";
//         let MINTER_ROLE = await noteToken.MINTER_ROLE();
//         await noteToken.grantRole(ADMIN_ROLE, accounts[0]);
//         await noteToken.grantRole(MINTER_ROLE, accounts[0]);
//         await noteToken.mint(accounts[0], amountBuy);

//         // await noteToken.approve(smAddress,amountBuy);
//         await noteToken.approve(tgeAddress,amountBuy);

//          const balanceBefore = await noteToken.balanceOf(newPool)
//          console.log(243, balanceBefore.toString())
//         const buyTX = await smContract.buyTokens(tgeAddress, amountBuy);
//         // console.log(239, buyTX.logs)
//         // console.log(240, buyTX)
//         const balanceAfter = await noteToken.balanceOf(newPool)
//         console.log(248, balanceAfter.toString())
//         // check the pool receive the currency
//         assert.equal(amountBuy, balanceAfter, "Fail to buy Token")
//         // https://alfajores.celoscan.io/tx/0x9e9e2f2842eab65bf8917bbd46f6e18e176d72ee9d986979230c553dd09c7d5c#eventlog
//     })
// })