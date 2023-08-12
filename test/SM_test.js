var fs = require('fs');
const {expectRevert} = require('@openzeppelin/test-helpers');
const { assert } = require('chai');
const { assembleFiles } = require('solidity-coverage/plugins/resources/plugin.utils');
const Registry = artifacts.require("Registry");
const SecuritizationPool = artifacts.require("SecuritizationPool");
const SecuritizationManager = artifacts.require("SecuritizationManager");
const LoanKernel = artifacts.require("LoanKernel"); 
const NoteToken = artifacts.require("NoteToken");
const NoteTokenFactory = artifacts.require("NoteTokenFactory");
const LoanAssetToken = artifacts.require("LoanAssetToken");
const MintedIncreasingInterestTGE = artifacts.require("MintedIncreasingInterestTGE");
const MintedNormalTGE = artifacts.require("MintedNormalTGE");
const TokenGenerationEventFactory = artifacts.require("TokenGenerationEventFactory"); 
const LoanInterestTermsContract = artifacts.require("LoanInterestTermsContract"); 
const LoanRepaymentRouter = artifacts.require("LoanRepaymentRouter"); 
contract('SecuritizationManager', (accounts) => {
    let smContract;
    let registry
    let smAddress;
    let registryAddress;
    let securitizationPool
    let mintedNormalTGE
    let loanAssetToken;
    let loanKernel
    let noteToken;
    let noteTokenFactory;
    let mintedIncreasingInterestTGE;
    let instanceMintedIncreasingInterestTGE;
    let instanceTGEJOT
    let tokenGenerationEventFactory;
    let registryInitialize
    let addressPool;
    let ADMIN_ROLE;
    let OWNER_ROLE;
    let myTokenAddress;
    let poolToSOT
    let poolToJOT
    var BN = web3.utils.BN;
    let sotToken;
    let jotToken;
    let tgeAddress;
    let tgeAddressJOT;
    let address;
    let loanRepaymentRouter
    let loanInterestTermsContract;
    before(async () => {
        registry = await Registry.new();
        address = await web3.eth.getAccounts()
        tokenGenerationEventFactory = await TokenGenerationEventFactory.new();
        // in protocol/fab
        mintedNormalTGE = await MintedNormalTGE.new();
        mintedIncreasingInterestTGE = await MintedIncreasingInterestTGE.new();
        loanInterestTermsContract = await LoanInterestTermsContract.new();
        loanRepaymentRouter = await LoanRepaymentRouter.new();
        // in fab
        loanAssetToken = await LoanAssetToken.new();
        // in tokens/erc721
      
        loanKernel = await LoanKernel.new();
        // in loan
        securitizationPool = await SecuritizationPool.new();
        // protocol/pool
        noteToken = await NoteToken.new("Test","TST", 18, securitizationPool.address,1);
        myTokenAddress = noteToken.address;
        smContract = await SecuritizationManager.new();
        // protocol/pool
        noteTokenFactory = await NoteTokenFactory.new()
        // protocol/pool
        smAddress = smContract.address;
        console.log(18, smAddress);      
        registryAddress = registry.address;
       
    })

    it('Should deploy SecuritizationManager contract properly', async () => {
        assert.notEqual(smAddress, 0x0);
        assert.notEqual(smAddress, '');
        assert.notEqual(smAddress, null);
        assert.notEqual(smAddress, undefined);

    });
    it('should initialize succesful ', async () => {
        await smContract.initialize(registryAddress);
         registryInitialize = await smContract.registry();
        assert.equal(registryAddress, registryInitialize, "succesful initialize Registry");
       
    })
    it('should grant Role succesful ', async () => {
        let CREATOR_POOL = await smContract.POOL_CREATOR();
        await smContract.grantRole(CREATOR_POOL, accounts[0]);
        let role = await smContract.hasRole(CREATOR_POOL, accounts[0]);
        assert.equal(true, role, "succesful grant Role creator Pool for admin");
    })

    it('create new pool succesful', async () => {
        console.log(42, accounts[0])
         OWNER_ROLE = await registry.OWNER_ROLE();
        ADMIN_ROLE = await registry.DEFAULT_ADMIN_ROLE();
        console.log(45, OWNER_ROLE, accounts[0]);
        await registry.initialize();

        await registry.setMintedIncreasingInterestTGE(mintedIncreasingInterestTGE.address)
        await registry.setNoteTokenFactory(noteTokenFactory.address);
        await registry.setTokenGenerationEventFactory(tokenGenerationEventFactory.address);
        await tokenGenerationEventFactory.initialize(registryAddress);
        await tokenGenerationEventFactory.grantRole(ADMIN_ROLE,accounts[0])
        await noteTokenFactory.initialize(registryAddress);
        await noteTokenFactory.grantRole(ADMIN_ROLE, accounts[0]);
        await loanKernel.initialize(registryAddress);
        await loanKernel.grantRole(ADMIN_ROLE, accounts[0]);
        await loanAssetToken.initialize(registryAddress,"TEST", "TST", "test.com" );
        await registry.grantRole(ADMIN_ROLE, accounts[0], {from:accounts[0]})
        await registry.setSecuritizationManager(smAddress);
        let securitizationPoolAddress = securitizationPool.address;
        await registry.setSecuritizationPool(securitizationPoolAddress)
        let loanAssetTokenAddress = loanAssetToken.address
        await registry.setLoanAssetToken(loanAssetTokenAddress);
        let loanKernelAddress = loanKernel.address
        await registry.setLoanKernel(loanKernelAddress);     
        await registry.setMintedNormalTGE(mintedNormalTGE.address)

        // loanInterestTermsContract = await LoanInterestTermsContract.new();
        // loanRepaymentRouter = await LoanRepaymentRouter.new();
        await loanInterestTermsContract.initialize(registryAddress);
        await loanRepaymentRouter.initialize(registryAddress);
        await registry.setLoanInterestTermsContract(loanInterestTermsContract.address);
        await registry.setLoanRepaymentRouter(loanRepaymentRouter.address);
        let minFirstLossCushion= 1234;
        await securitizationPool.initialize(registryAddress, myTokenAddress,minFirstLossCushion);        
        await smContract.grantRole(ADMIN_ROLE, accounts[0])
        const transaction = await smContract.newPoolInstance(myTokenAddress, minFirstLossCushion);        
   
      
        let logs = transaction.logs
        // console.log(122, logs)
         addressPool = logs[7]['args'][0]
        console.log(124,addressPool)
        // console.log(78, transaction.receipt.logs, )
        let isPool = await smContract.isExistingPools(addressPool);
        console.log(127, isPool)
        assert.equal(true, isPool, "succesful creae new Pool instance");
    
        let poolExist = await smContract.isExistingPools(addressPool);
        console.log(141, poolExist);
        assert.equal(true, poolExist, "succesful create new  Pool Instance");
    });
    // it('initialie SOT successful', async () => {
    //     let txSOT = await smContract.initialTGEForSOT(
    //         accounts[0],
    //         addressPool,
    //         0,
    //         18,
    //         true
    //     )  
    //     // console.log(138, txSOT.logs, txSOT.logs[10].args.instanceAddress, txSOT.logs[11].args.instanceAddress)
  
    //     poolToSOT = await smContract.poolToSOT(addressPool);
    //     // console.log(138, poolToSOT, tgeAddress, sotToken)
    //     assert.notEqual(poolToSOT, 0x0, "Fail on creating SOT");
    // })

    // it(' should initialize succesful TGE for JOT ', async () => {   
    //     let txJOT = await smContract.initialTGEForJOT(
    //         accounts[0],
    //         addressPool,
    //         0,
    //         18,
    //         true
    //     )
    //     console.log(151, txJOT)
    //     tgeAddressJOT = txJOT.logs[10].args.instanceAddress
    //     jotToken = txJOT.logs[11].args.instanceAddress 
    //     poolToJOT = await smContract.poolToJOT(addressPool);
    //     // console.log(152, poolToJOT)
    //     assert.notEqual(poolToJOT, 0x0, "Fail on creating JOT");
    // })

    it(' Should  set up TGE for SOT succesful', async () => {
        let openingTime = 1689590489;
         
        let closingTime =1697539289 ;
        let rate =2 ;
        let cap = Math.pow(10,18);
   
        cap = cap.toString();
        // cap = new BN(cap)
        console.log(163, cap, accounts[0], address[0])
        const txSetup = await smContract.setUpTGEForSOT(
            accounts[1],
            addressPool,
            0,
            18,
            true,
    
            cap,
    
            2,
            3,
            4,
            100,
            {openingTime,closingTime,rate,cap}
        )
        // console.log(201, txSetup.logs)
        tgeAddress = txSetup.logs[10].args.instanceAddress
        sotToken = txSetup.logs[11].args.instanceAddress 
        let tgeValid =await smContract.isExistingTGEs(tgeAddress)
        console.log(204, tgeValid)
        assert.equal(tgeValid, true, "Fail to set up TGE for SOT")
    })

    it(' Should  SET UP TGE for JOT succesful', async () => {
        // await mintedNormalTGE.initialize(registryAddress, addressPool, , myTokenAddress, true)
        let openingTime = 1689790489;
         
        let closingTime =1698539289 ;
        let rate =4 ;
        let cap = Math.pow(10,19);
   
        cap = cap.toString();
        // cap = new BN(cap)
        console.log(233, cap, accounts[0], address[0])
        const txJOT = await smContract.setUpTGEForJOT(
            accounts[2],
            addressPool,
            1,
            18,
            true,    
            cap,   
            {openingTime,closingTime,rate,cap}
        )
        console.log(227, txJOT)
        tgeAddressJOT = txJOT.logs[10].args.instanceAddress
        jotToken = txJOT.logs[11].args.instanceAddress 
        instanceTGEJOT = await MintedIncreasingInterestTGE.at(tgeAddressJOT);
        let tgeValid =await smContract.isExistingTGEs(tgeAddressJOT)
        console.log(231, tgeValid)
        assert.equal(tgeValid, true, "Fail to set up TGE for JOT")

        // await instanceTGEJOT.setInterestRange(2,3,4,100)
               
        // const txStart =  await instanceTGEJOT.startNewRoundSale(
        //         openingTime,
        //         closingTime,
        //         rate,
        //         cap
        //     )
        // console.log(248, txStart.logs)
        // let closeTimeData = await instanceTGEJOT.closingTime()
                 
        // closeTimeData= closeTimeData.toString()
        // console.log(193, closeTimeData);
             
     
        // assert.equal(closingTime.toString(), closeTimeData, "Fail to start new Round Sale")
    })

    it(' Should buy SOT token successfully ', async () => { 
        let sotInstance = await NoteToken.at(sotToken);
        let balanceSOTBefore = await sotInstance.balanceOf(accounts[0]);
        console.log(255, tgeAddress);
        let MINTER_ROLE = await noteToken.MINTER_ROLE();
        await noteToken.grantRole(ADMIN_ROLE, accounts[0]);
        await noteToken.grantRole(MINTER_ROLE, accounts[0]);
        await noteToken.mint(accounts[0],"100000000000000000" );
        await noteToken.approve(tgeAddress,"100000000000000000");
        await smContract.buyTokens(tgeAddress, "100000000000000000");
        
        let balanceSOT = await sotInstance.balanceOf(accounts[0]);
        assert.equal(balanceSOT >balanceSOTBefore, true, "Fail to buy SOT ")
    })

    it(' Should buy JOT token successfully ', async () => { 
        let jotInstance = await NoteToken.at(jotToken);
        let balanceJOTBefore = await jotInstance.balanceOf(accounts[0]);
        let MINTER_ROLE = await noteToken.MINTER_ROLE();
        await noteToken.mint(accounts[0],"1000000000000000000" );
        await noteToken.approve(tgeAddressJOT,"100000000000000000");
        await smContract.buyTokens(tgeAddressJOT, "100000000000000000");
        
        let balanceJOT = await jotInstance.balanceOf(accounts[0]);
        assert.equal(balanceJOT >balanceJOTBefore, true, "Fail to buy SOT ")
    })

    // it(" should fill debt order successful", async () => {
    //     // await loanKernel.fillDebtOrder()
    //     let orderAddresses = [
    //         accounts[1],
    //         myTokenAddress,
    //         loanRepaymentRouter.address,
    //         loanInterestTermsContract
    //     ];
    //     let orderValues = [
    //         2,3
    //     ];
    //     let termsContractParameters = [];
    //     let tokenIds = [1,2];
    //     await loanKernel.fillDebtOrder(
    //           orderAddresses, // 0-creditor, 1-principal token address, 2-repayment router, 3-term contract, 4-relayer,...
    //           orderValues, //  0-creditorFee, 1-asset purpose,..., [x] principalAmounts, [x] expirationTimestampInSecs, [x] - salts, [x] - riskScores
    //           termsContractParameters, // Term contract parameters from different farmers, encoded as hash strings
    //           tokenIds
    //     );
    // })
})