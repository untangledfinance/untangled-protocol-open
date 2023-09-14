const { networks } = require('../networks');

task('setup-receiver', 'Setup receiver').setAction(async (taskArgs, hre) => {
  const { deployments } = hre;
  const bnmToken = networks[network.name].bnmToken;
  if (!bnmToken) {
    throw Error('Missing BNM Token Address');
  }

  const ROUTER = networks[network.name].router;
  const LINK = networks[network.name].linkToken;
  const LINK_AMOUNT = '0.5';
  const TOKEN_TRANSFER_AMOUNT = '0.0001';

  const [deployer] = await ethers.getSigners();

  const untangledReceiver = await deployments.get('UntangledReceiver');

  const receiverContractAddress = untangledReceiver.address;

  // Fund with LINK
  console.log(`\nFunding ${receiverContractAddress} with ${LINK_AMOUNT} LINK `);
  const LinkTokenFactory = await ethers.getContractFactory('@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20');
  const linkTokenContract = await LinkTokenFactory.attach(networks[network.name].linkToken);

  // Transfer LINK tokens to the contract
  const linkTx = await linkTokenContract.transfer(receiverContractAddress, ethers.utils.parseEther(LINK_AMOUNT));
  await linkTx.wait(1);

  console.log(`\nFunding ${receiverContractAddress} with ${TOKEN_TRANSFER_AMOUNT} CCIP-BnM ${bnmToken}`);
  const bnmTokenContract = await ethers.getContractAt('@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20', bnmToken);

  const bnmTokenTx = await bnmTokenContract.transfer(
    receiverContractAddress,
    ethers.utils.parseUnits(TOKEN_TRANSFER_AMOUNT)
  );
  await bnmTokenTx.wait(1);

  const bnmTokenBal_baseUnits = await bnmTokenContract.balanceOf(receiverContractAddress);
  const bnmTokenBal = ethers.utils.formatUnits(bnmTokenBal_baseUnits.toString());
  console.log(`\nFunded ${receiverContractAddress} with ${bnmTokenBal} CCIP-BnM`);

  const juelsBalance = await linkTokenContract.balanceOf(receiverContractAddress);
  const linkBalance = ethers.utils.formatEther(juelsBalance.toString());
  console.log(`\nFunded ${receiverContractAddress} with ${linkBalance} LINK`);
});
