var fs = require('fs');
const { expectRevert } = require('@openzeppelin/test-helpers');
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
const DistributionAssessor = artifacts.require("DistributionAssessor");

const SecuritizationPoolValueService = artifacts.require("SecuritizationPoolValueService");
contract('DistributionAssessor', (accounts) => {
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
    let distributionAssessor;
    let distributionAssessorAddress;
    let securitizationPoolValueService;
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
    let sotInstance;
    let jotToken;
    let jotinstanc
    let tgeAddress;
    let tgeAddressJOT;
    let address;
    let loanRepaymentRouter
    let loanInterestTermsContract;
    before(async () => {
        registry = await Registry.new();
        address = await web3.eth.getAccounts()
        tokenGenerationEventFactory = await TokenGenerationEventFactory.new();
        distributionAssessor = await DistributionAssessor.new();
        
        securitizationPoolValueService = await SecuritizationPoolValueService.new();
        distributionAssessorAddress = distributionAssessor.address;
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
        noteToken = await NoteToken.new("Test", "TST", 18, securitizationPool.address, 1);
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
        assert.notEqual(distributionAssessorAddress, 0x0);
        assert.notEqual(distributionAssessorAddress, '');
        assert.notEqual(distributionAssessorAddress, null);
        assert.notEqual(distributionAssessorAddress, undefined);

    });
    it('should initialize succesful ', async () => {
        await smContract.initialize(registryAddress);
        registryInitialize = await smContract.registry();
        assert.equal(registryAddress, registryInitialize, "succesful initialize Registry");

    })
    it('should grant Role succesful ', async () => {
        OWNER_ROLE = await registry.OWNER_ROLE();
        ADMIN_ROLE = await registry.DEFAULT_ADMIN_ROLE();
        let CREATOR_POOL = await smContract.POOL_CREATOR();
        await smContract.grantRole(CREATOR_POOL, accounts[0]);
        await distributionAssessor.initialize(registryAddress);
        await distributionAssessor.grantRole(ADMIN_ROLE, accounts[0]);
        let role = await smContract.hasRole(CREATOR_POOL, accounts[0]);
        assert.equal(true, role, "succesful grant Role creator Pool for admin");
    })

    it('get JOT Price successful ', async () => {
        console.log(42, accounts[0])       
        console.log(45, OWNER_ROLE, accounts[0]);
        await registry.initialize();
        await registry.setMintedIncreasingInterestTGE(mintedIncreasingInterestTGE.address)
        await registry.setNoteTokenFactory(noteTokenFactory.address);
        await registry.setDistributionAssessor(distributionAssessor.address);
        await registry.setTokenGenerationEventFactory(tokenGenerationEventFactory.address);
        await tokenGenerationEventFactory.initialize(registryAddress);
        await tokenGenerationEventFactory.grantRole(ADMIN_ROLE, accounts[0])
        await noteTokenFactory.initialize(registryAddress);
        await noteTokenFactory.grantRole(ADMIN_ROLE, accounts[0]);
        await loanKernel.initialize(registryAddress);
        await loanKernel.grantRole(ADMIN_ROLE, accounts[0]);
        await loanAssetToken.initialize(registryAddress, "TEST", "TST", "test.com");
        await registry.grantRole(ADMIN_ROLE, accounts[0], { from: accounts[0] })
        await registry.setSecuritizationManager(smAddress);
        let securitizationPoolAddress = securitizationPool.address;
        await registry.setSecuritizationPool(securitizationPoolAddress)
        let loanAssetTokenAddress = loanAssetToken.address
        await registry.setLoanAssetToken(loanAssetTokenAddress);
        let loanKernelAddress = loanKernel.address
        await registry.setLoanKernel(loanKernelAddress);
        await registry.setMintedNormalTGE(mintedNormalTGE.address) 
        await loanInterestTermsContract.initialize(registryAddress);
        await loanRepaymentRouter.initialize(registryAddress);
        await registry.setLoanInterestTermsContract(loanInterestTermsContract.address);
        await registry.setLoanRepaymentRouter(loanRepaymentRouter.address);
        let minFirstLossCushion = 12;
        await securitizationPool.initialize(registryAddress, myTokenAddress, minFirstLossCushion);
        await smContract.grantRole(ADMIN_ROLE, accounts[0])
        const transaction = await smContract.newPoolInstance(myTokenAddress, minFirstLossCushion);
        let logs = transaction.logs
        // console.log(122, logs)
        addressPool = logs[7]['args'][0]
        console.log(124, addressPool)
        // console.log(78, transaction.receipt.logs, )
        let isPool = await smContract.isExistingPools(addressPool);
        console.log(127, isPool)
        assert.equal(true, isPool, "succesful creae new Pool instance");   
        let openingTime = 1689590489;
        let closingTime = 1697539289;
        let rate = 2;
        let cap = Math.pow(10, 18);
        cap = cap.toString();
 
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
            { openingTime, closingTime, rate, cap }
        )
 
        tgeAddress = txSetup.logs[10].args.instanceAddress;
        sotToken = txSetup.logs[11].args.instanceAddress;  
        sotInstance = await NoteToken.at(sotToken);
        const txJOT = await smContract.setUpTGEForJOT(
            accounts[2],
            addressPool,
            1,
            18,
            true,
            cap,
            { openingTime, closingTime, rate, cap }
        )
        // console.log(227, txJOT)
        tgeAddressJOT = txJOT.logs[10].args.instanceAddress
        jotToken = txJOT.logs[11].args.instanceAddress
        instanceTGEJOT = await MintedIncreasingInterestTGE.at(tgeAddressJOT);
        jotInstance = await NoteToken.at(jotToken);
         
        let MINTER_ROLE = await noteToken.MINTER_ROLE();
        await noteToken.grantRole(ADMIN_ROLE, accounts[0]);
        await noteToken.grantRole(MINTER_ROLE, accounts[0]);
        await noteToken.mint(accounts[0], "100000000000000000");
        await noteToken.approve(tgeAddress, "100000000000000000");
        await smContract.buyTokens(tgeAddress, "100000000000000000");
       
        jotInstance = await NoteToken.at(jotToken);
        // let balanceJOTBefore = await jotInstance.balanceOf(accounts[0]);
     
        await noteToken.mint(accounts[0], "1000000000000000000");
        await noteToken.approve(tgeAddressJOT, "100000000000000000");
        await smContract.buyTokens(tgeAddressJOT, "100000000000000000");

        await registry.setSecuritizationPoolValueService(securitizationPoolValueService.address);
        await distributionAssessor.setPoolService(securitizationPoolValueService.address);
        await securitizationPoolValueService.initialize(registryAddress);
        let beginingiSeniorDebt = await securitizationPoolValueService.getBeginningSeniorDebt(addressPool);
        console.log(232, beginingiSeniorDebt.toString())
  
        let pool = await SecuritizationPool.at(addressPool);
        console.log(255, await pool.jotToken());
        const JOTPrice = await distributionAssessor.getJOTTokenPrice(addressPool,1698539289 )
        console.log(257, JOTPrice.toString())
        let totalJOT = await jotInstance.totalSupply();
        console.log(239, totalJOT.toString())
        let juniorAsset = await securitizationPoolValueService.getJuniorAsset(addressPool);
        let jotPriceCalculcate = juniorAsset/totalJOT;
        console.log(242, jotPriceCalculcate)
        assert.equal(JOTPrice.toString(), jotPriceCalculcate.toString(), "Fail to get price of JOT ")
    })

    it(' Get SOT token price successful', async() => { 
        let totalSOT = await sotInstance.totalSupply();
        console.log(244, totalSOT.toString())   
        let seniorAsset =await securitizationPoolValueService.getSeniorAsset(addressPool); 
        let priceSOTCalculate =   seniorAsset/ totalSOT;
        console.log(250, priceSOTCalculate)
        const SOTPrice = await distributionAssessor.getSOTTokenPrice(addressPool,1698539289 )
        console.log(262, SOTPrice.toString())
        assert.equal(SOTPrice , priceSOTCalculate, "Fail to get price of SOT ")
    })

})