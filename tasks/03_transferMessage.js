const { networks } = require('../networks');

task('transfer-message', 'transfers token x-chain from Sender.sol to Protocol.sol')
  .addParam('receiver', 'address of Receiver')
  .addParam('destchain', 'destination chain as specified in networks.js file')
  .setAction(async (taskArgs, hre) => {
    const { deployments, ethers } = hre;

    const [deployer] = await ethers.getSigners();

    const { parseEther, defaultAbiCoder } = ethers.utils;
    const abiCoder = new ethers.utils.AbiCoder();

    let { sender, receiver, destchain } = taskArgs;

    let destChainSelector = networks[destchain].chainSelector;

    const senderFactory = await ethers.getContractFactory('UntangledSender');
    const untangledSender = await deployments.get('UntangledSender');
    const senderContract = await senderFactory.attach(untangledSender.address);

    const userData = abiCoder.encode(['address', 'uint256'], [deployer.address, parseEther('100')]);

    const sendTokensTx = await senderContract.sendMessage(
      destChainSelector,
      receiver,
      {
        messageType: 0,
        data: userData,
      },
      '100000'
    );
    await sendTokensTx.wait();
    console.log('\nTx hash is ', sendTokensTx.hash);

    console.log(`\nPlease visit the CCIP Explorer at 'https://ccip.chain.link' and paste in the Tx Hash '${sendTokensTx.hash}' to view the status of your CCIP tx.
    Be sure to make a note of your Message Id for use in the next steps.`);
  });
