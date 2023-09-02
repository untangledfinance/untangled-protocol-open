var fs = require('fs');
const { expectRevert } = require('@openzeppelin/test-helpers');
const { assert } = require('chai');

const Registry = artifacts.require('Registry');
const SecuritizationPool = artifacts.require('SecuritizationPool');
const SecuritizationManager = artifacts.require('SecuritizationManager');
const LoanKernel = artifacts.require('LoanKernel');
const NoteToken = artifacts.require('NoteToken');
const NoteTokenFactory = artifacts.require('NoteTokenFactory');
const LoanAssetToken = artifacts.require('LoanAssetToken');
const MintedIncreasingInterestTGE = artifacts.require('MintedIncreasingInterestTGE');
const MintedNormalTGE = artifacts.require('MintedNormalTGE');
const TokenGenerationEventFactory = artifacts.require('TokenGenerationEventFactory');
const LoanInterestTermsContract = artifacts.require('LoanInterestTermsContract');
const LoanRepaymentRouter = artifacts.require('LoanRepaymentRouter');
const DistributionAssessor = artifacts.require('DistributionAssessor');

const SecuritizationPoolValueService = artifacts.require('SecuritizationPoolValueService');
var BigNumber = require('bignumber.js');
contract('SecuritizationPoolValueService', (accounts) => {
  let smContract;
  let registry;
  let smAddress;
  let registryAddress;
  let securitizationPool;
  let mintedNormalTGE;
  let loanAssetToken;
  let loanKernel;
  let noteToken;
  let noteTokenFactory;
  let mintedIncreasingInterestTGE;
  let instanceMintedIncreasingInterestTGE;
  let distributionAssessor;
  let distributionAssessorAddress;
  let securitizationPoolValueService;
  let securitizationPoolValueServiceAddress;
  let instanceTGEJOT;
  let tokenGenerationEventFactory;
  let registryInitialize;
  let addressPool;
  let ADMIN_ROLE;
  let OWNER_ROLE;
  let myTokenAddress;
  let poolInstance;
  let poolToSOT;
  let poolToJOT;
  var BN = web3.utils.BN;
  let sotToken;
  let sotInstance;
  let jotToken;
  let jotinstanc;
  let tgeAddress;
  let tgeAddressJOT;
  let address;
  let loanRepaymentRouter;
  let loanInterestTermsContract;
  let timeNow;
  before(async () => {
    registry = await Registry.new();
    address = await web3.eth.getAccounts();
    tokenGenerationEventFactory = await TokenGenerationEventFactory.new();
    distributionAssessor = await DistributionAssessor.new();

    securitizationPoolValueService = await SecuritizationPoolValueService.new();
    securitizationPoolValueServiceAddress = securitizationPoolValueService.address;
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
    noteToken = await NoteToken.new('Test', 'TST', 18, securitizationPool.address, 1);
    myTokenAddress = noteToken.address;
    smContract = await SecuritizationManager.new();
    // protocol/pool
    noteTokenFactory = await NoteTokenFactory.new();
    // protocol/pool
    smAddress = smContract.address;
    console.log(18, smAddress);
    registryAddress = registry.address;
    await smContract.initialize(registryAddress);
    registryInitialize = await smContract.registry();
    OWNER_ROLE = await registry.OWNER_ROLE();
    ADMIN_ROLE = await registry.DEFAULT_ADMIN_ROLE();
    let CREATOR_POOL = await smContract.POOL_CREATOR();
    await smContract.grantRole(CREATOR_POOL, accounts[0]);
    await distributionAssessor.initialize(registryAddress);
    await distributionAssessor.grantRole(ADMIN_ROLE, accounts[0]);
  });

  it('Should deploy SecuritizationPoolValueService contract properly', async () => {
    assert.notEqual(securitizationPoolValueServiceAddress, 0x0);
    assert.notEqual(securitizationPoolValueServiceAddress, '');
    assert.notEqual(securitizationPoolValueServiceAddress, null);
    assert.notEqual(securitizationPoolValueServiceAddress, undefined);
  });
  it('should initialize succesful ', async () => {
    await securitizationPoolValueService.initialize(registryAddress);
    let securitizationPoolValueServiceInitialize = await smContract.registry();
    assert.equal(registryAddress, securitizationPoolValueServiceInitialize, 'succesful initialize Registry');
  });
  it('should grant Role succesful ', async () => {
    await securitizationPoolValueService.grantRole(ADMIN_ROLE, accounts[0]);
    let role = await securitizationPoolValueService.hasRole(ADMIN_ROLE, accounts[0]);
    assert.equal(true, role, 'succesful grant Role creator Pool for admin');
  });

  it('get Net Asset Value  correct ', async () => {
    await registry.initialize();
    await registry.setMintedIncreasingInterestTGE(mintedIncreasingInterestTGE.address);
    await registry.setNoteTokenFactory(noteTokenFactory.address);
    await registry.setDistributionAssessor(distributionAssessor.address);
    await registry.setTokenGenerationEventFactory(tokenGenerationEventFactory.address);
    await tokenGenerationEventFactory.initialize(registryAddress);
    await tokenGenerationEventFactory.grantRole(ADMIN_ROLE, accounts[0]);
    await noteTokenFactory.initialize(registryAddress);
    await noteTokenFactory.grantRole(ADMIN_ROLE, accounts[0]);
    await loanKernel.initialize(registryAddress);
    await loanKernel.grantRole(ADMIN_ROLE, accounts[0]);
    await loanAssetToken.initialize(registryAddress, 'TEST', 'TST', 'test.com');
    await registry.grantRole(ADMIN_ROLE, accounts[0], { from: accounts[0] });
    await registry.setSecuritizationManager(smAddress);
    let securitizationPoolAddress = securitizationPool.address;
    await registry.setSecuritizationPool(securitizationPoolAddress);
    let loanAssetTokenAddress = loanAssetToken.address;
    await registry.setLoanAssetToken(loanAssetTokenAddress);
    let loanKernelAddress = loanKernel.address;
    await registry.setLoanKernel(loanKernelAddress);
    await registry.setMintedNormalTGE(mintedNormalTGE.address);
    await loanInterestTermsContract.initialize(registryAddress);
    await loanRepaymentRouter.initialize(registryAddress);
    await registry.setLoanInterestTermsContract(loanInterestTermsContract.address);
    await registry.setLoanRepaymentRouter(loanRepaymentRouter.address);
    let minFirstLossCushion = 120000;
    await securitizationPool.initialize(registryAddress, myTokenAddress, minFirstLossCushion);
    await smContract.grantRole(ADMIN_ROLE, accounts[0]);
    const transaction = await smContract.newPoolInstance(myTokenAddress, minFirstLossCushion);
    let logs = transaction.logs;
    // console.log(122, logs)
    addressPool = logs[7]['args'][0];
    console.log(124, addressPool);
    // console.log(78, transaction.receipt.logs, )
    let isPool = await smContract.isExistingPools(addressPool);
    console.log(127, isPool);
    assert.equal(true, isPool, 'succesful creae new Pool instance');
    let openingTime = 1689590489;
    let closingTime = 1697539289;
    let rate = 100;
    let cap = Math.pow(10, 18);
    cap = cap.toString();

    console.log(163, cap, accounts[0], address[0]);
    const txSetup = await smContract.setUpTGEForSOT(
      accounts[1],
      addressPool,
      [0, 18],
      true,
      cap,
      100000,
      100000,
      86400,
      0,
      { openingTime: openingTime, closingTime: closingTime, rate: rate, cap: cap },
      'SOT'
    );

    tgeAddress = txSetup.logs[10].args.instanceAddress;
    sotToken = txSetup.logs[11].args.instanceAddress;
    sotInstance = await NoteToken.at(sotToken);
    const txJOT = await smContract.setUpTGEForJOT(
      accounts[2],
      addressPool,
      [1, 18],
      true,
      cap,
      { openingTime: openingTime, closingTime: closingTime, rate: rate, cap: cap },
      'JOT'
    );
    // console.log(227, txJOT)
    tgeAddressJOT = txJOT.logs[10].args.instanceAddress;
    jotToken = txJOT.logs[11].args.instanceAddress;
    instanceTGEJOT = await MintedIncreasingInterestTGE.at(tgeAddressJOT);
    jotInstance = await NoteToken.at(jotToken);

    let MINTER_ROLE = await noteToken.MINTER_ROLE();
    await noteToken.grantRole(ADMIN_ROLE, accounts[0]);
    await noteToken.grantRole(MINTER_ROLE, accounts[0]);
    await noteToken.mint(accounts[0], '100000000000000000');
    await noteToken.approve(tgeAddress, '100000000000000000');
    await smContract.buyTokens(tgeAddress, '100000000000000000');

    jotInstance = await NoteToken.at(jotToken);
    // let balanceJOTBefore = await jotInstance.balanceOf(accounts[0]);

    await noteToken.mint(accounts[0], '1000000000000000000');
    await noteToken.approve(tgeAddressJOT, '100000000000000000');
    await smContract.buyTokens(tgeAddressJOT, '100000000000000000');

    await registry.setSecuritizationPoolValueService(securitizationPoolValueService.address);
    // await distributionAssessor.setPoolService(securitizationPoolValueService.address);

    poolInstance = await SecuritizationPool.at(addressPool);
    console.log(219, await poolInstance.jotToken());

    timeNow = Math.round(Date.now());
    console.log(221, timeNow);
    let expectedNAV = await securitizationPoolValueService.getExpectedAssetsValue(addressPool, timeNow);
    console.log(223, expectedNAV.toString());
    assert.equal(expectedNAV.toString(), 0, 'Fail to get NAV ');
  });

  it(' Get Pool Value correctly ', async () => {
    // let timeNow = Math.round(Date.now() );
    console.log(231, timeNow);
    let getPoolValue = await securitizationPoolValueService.getPoolValue(addressPool);
    let nAVpoolValue = await securitizationPoolValueService.getExpectedAssetsValue(addressPool, timeNow);
    let currencyAddress = await poolInstance.underlyingCurrency();
    let instanceCurrency = await NoteToken.at(currencyAddress);
    let reserve = await instanceCurrency.balanceOf(addressPool);
    reserve = BigNumber.from(reserve.toString());
    nAVpoolValue = BigNumber.from(nAVpoolValue.toString());
    console.log(234, reserve.toString(), nAVpoolValue.toString());
    let poolValue = nAVpoolValue.plus(reserve);
    console.log(236, poolValue.toString(), getPoolValue.toString());
    assert.equal(poolValue.toString(), getPoolValue.toString(), 'Fail to correct Pool value');
  });

  it(' Get Senior asset  correctly ', async () => {
    let poolValue = await securitizationPoolValueService.getPoolValue(addressPool);
    console.log(245, poolValue.toString());
    let seniorBalance = await securitizationPoolValueService.getSeniorBalance(addressPool);
    console.log(247, seniorBalance.toString());
    let rateSenior = await securitizationPoolValueService.getSeniorRatio(addressPool);
    console.log(247, rateSenior.toString());

    let beginningSeniorAsset = await securitizationPoolValueService.getBeginningSeniorAsset(addressPool);
    console.log(248, beginningSeniorAsset.toString());
    let expectedAssetsValue = await securitizationPoolValueService.getExpectedAssetsValue(addressPool, timeNow);
    console.log(249, expectedAssetsValue.toString());
    let senorDebt = await securitizationPoolValueService.getSeniorDebt(addressPool);
    console.log(256, senorDebt.toString());

    let expectedSeniorAsset = await securitizationPoolValueService.getExpectedSeniorAssets(addressPool);
    console.log(259, expectedSeniorAsset.toString());
    let seniorAsset = await securitizationPoolValueService.getSeniorAsset(addressPool);
    console.log(261, seniorAsset.toString());
  });

  it(' Get Expected Senior asset  correctly ', async () => {
    let getExpectedSeniorAssets = await securitizationPoolValueService.getExpectedSeniorAssets(addressPool);
    console.log(263, getExpectedSeniorAssets.toString());
  });

  it(' Get  Senior debt  correctly ', async () => {
    let getBeginningSeniorDebt = await securitizationPoolValueService.getBeginningSeniorDebt(addressPool);
    console.log(271, getBeginningSeniorDebt.toString());
    let getSeniorDebt = await securitizationPoolValueService.getSeniorDebt(addressPool);
    console.log(268, getSeniorDebt.toString());
  });

  it(' Get  Senior Balance  correctly ', async () => {
    let getSeniorBalance = await securitizationPoolValueService.getSeniorBalance(addressPool);
    console.log(276, getSeniorBalance.toString());
  });

  it(' Get  Junior Asset correctly ', async () => {
    let getJuniorAsset = await securitizationPoolValueService.getJuniorAsset(addressPool);
    console.log(282, getJuniorAsset.toString());
  });

  it(' Get  Senior Ratio correctly ', async () => {
    let getSeniorRatio = await securitizationPoolValueService.getSeniorRatio(addressPool);
    console.log(275, getSeniorRatio.toString());
  });

  it(' Get  Junior Ratio correctly ', async () => {
    let getJuniorRatio = await securitizationPoolValueService.getJuniorRatio(addressPool);
    console.log(280, getJuniorRatio.toString());
  });
});
