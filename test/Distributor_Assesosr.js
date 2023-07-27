const {expectRevert} = require('@openzeppelin/test-helpers');
const { assert } = require('chai');
const { assembleFiles } = require('solidity-coverage/plugins/resources/plugin.utils');
const Registry = artifacts.require("Registry");
const SecuritizationPool = artifacts.require("SecuritizationPool");
const SecuritizationManager = artifacts.require("SecuritizationManager");
const DistributionAssessor = artifacts.require("DistributionAssessor");
const LoanKernel = artifacts.require("LoanKernel");

const NoteToken = artifacts.require("NoteToken");
const NoteTokenFactory = artifacts.require("NoteTokenFactory");
const LoanAssetToken = artifacts.require("LoanAssetToken");
const MintedIncreasingInterestTGE = artifacts.require("MintedIncreasingInterestTGE");
const TokenGenerationEventFactory = artifacts.require("TokenGenerationEventFactory");
// MintedNormalTGE
contract('DistributionAssessor', (accounts) => {
    let smContract;
    let registry
    let smAddress;
    let registryAddress;
    let securitizationPool
   
    let distributionAssessor;
    let loanAssetToken;
    let loanKernel
    let noteToken;
    let noteTokenFactory;
    let mintedIncreasingInterestTGE;
    let tokenGenerationEventFactory;
    // let registryInitialize
    let addressPool;
    let ADMIN_ROLE;
    let OWNER_ROLE;
    let myTokenAddress;
    let poolToSOT
    let poolToJOT
    var BN = web3.utils.BN;
    let distributionAssessorAddress;
    before(async () => {
        registry = await Registry.new();
         
        distributionAssessor = await DistributionAssessor.new();
        tokenGenerationEventFactory = await TokenGenerationEventFactory.new();
        // in protocol/fab
        mintedIncreasingInterestTGE = await MintedIncreasingInterestTGE.new();
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
        distributionAssessorAddress = distributionAssessor.address;

        console.log(18, smAddress);
      
        registryAddress = registry.address;
        await smContract.initialize(registryAddress);
        const CREATOR_POOL = await smContract.POOL_CREATOR();
        
        await smContract.grantRole(CREATOR_POOL, accounts[0]);
    })

    it('Should deploy DistributionAssessor contract properly', async () => {
        assert.notEqual(distributionAssessorAddress, 0x0);
        assert.notEqual(distributionAssessorAddress, '');
        assert.notEqual(distributionAssessorAddress, null);
        assert.notEqual(distributionAssessorAddress, undefined);

    });
    it('should initialize succesful ', async () => {
        await distributionAssessor.initialize(registryAddress);
        const distributeAssessorInitialize = await distributionAssessor.registry();
        assert.equal(registryAddress, distributeAssessorInitialize, "succesful initialize Registry");
       
    })
    it('should grant Role succesful ', async () => {
        ADMIN_ROLE = await registry.DEFAULT_ADMIN_ROLE();

        await distributionAssessor.grantRole(ADMIN_ROLE, accounts[0])
        const role = await distributionAssessor.hasRole(ADMIN_ROLE, accounts[0]);
        assert.equal(true, role, "succesful grant Role admin for admin");
    })

    it('create new pool succesful', async () => {
        console.log(42, accounts[0])
         OWNER_ROLE = await registry.OWNER_ROLE();
        
        console.log(45, OWNER_ROLE, accounts[0]);
        await registry.initialize();
        await registry.setMintedIncreasingInterestTGE(mintedIncreasingInterestTGE.address);
        await registry.setNoteTokenFactory(noteTokenFactory.address);
        await registry.setTokenGenerationEventFactory(tokenGenerationEventFactory.address);
        await registry.setDistributionAssessor(distributionAssessor.address);
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
        
        let minFirstLossCushion= 1234;
        await securitizationPool.initialize(registryAddress, myTokenAddress,minFirstLossCushion);        
        await smContract.grantRole(ADMIN_ROLE, accounts[0])
        const transaction = await smContract.newPoolInstance(myTokenAddress, minFirstLossCushion);        
        let arrReceiptLogs = []
        arrReceiptLogs.push(transaction.receipt.logs)
      
        let logs = transaction.logs
      
         addressPool = logs[7]['args'][0]
        console.log(90,addressPool)
        let txSOT = await smContract.initialTGEForSOT(
            accounts[0],
            addressPool,
            0,
            18,
            true
        )  
        
 
        poolToSOT = await smContract.poolToSOT(addressPool);
        let txJOT = await smContract.initialTGEForJOT(
            accounts[0],
            addressPool,
            0,
            18,
            true
        )
         poolToJOT = await smContract.poolToJOT(addressPool);
    // });
    // it('initialie SOT successful', async () => {
       
        
    // })
    // it(' should initialize succesful TGE for JOT ', async () => {
   
       
    //     console.log(152, poolToJOT)
    //     assert.notEqual(poolToJOT, 0x0, "Fail on creating JOT");
    // })

    // it(' Should  start new round sale succesful', async () => {
        let openingTime = 1689590489;
         
        let closingTime =1697539289 ;
        let rate =2 ;
        let cap = Math.pow(10,18);
        console.log(162, cap )
        cap = cap.toString();
        // cap = new BN(cap)
        console.log(163, cap)
        await mintedIncreasingInterestTGE.initialize(
            registryAddress,
            addressPool,
            poolToSOT,
            myTokenAddress, 
            true
        )
        await mintedIncreasingInterestTGE.setInterestRange(2,3,4,100);
        await mintedIncreasingInterestTGE.startNewRoundSale(
             openingTime,
             closingTime,
             rate,
             cap
        )
        // let closeTime = await mintedIncreasingInterestTGE.closingTime();
        
        // console.log(180, closeTime);
        // assert.equal(closeTime, closingTime, "Fail to start new Round Sale")
    // })
    // it(' Should buy token successfully ', async () => {
        let tgeAddress = await tokenGenerationEventFactory.tgeAddresses(0);
        console.log(187, tgeAddress);
        let MINTER_ROLE = await noteToken.MINTER_ROLE();
        await noteToken.grantRole(ADMIN_ROLE, accounts[0]);
        await noteToken.grantRole(MINTER_ROLE, accounts[0]);
        await noteToken.mint(accounts[0],"100000000000000000" );
        await noteToken.approve(mintedIncreasingInterestTGE.address,"100000000000000000");
        await noteToken.approve(smAddress,"100000000000000000");
        // console.log(193, mintedIncreasingInterestTGE.address)
        // await mintedIncreasingInterestTGE.buyTokens(accounts[0],accounts[0], "100000000000000000");
        await smContract.buyTokens(tgeAddress, "100000000000000000");
    })
})