const { networks } = require('../networks');

task('get-info-receiver', 'Get info from receiver').setAction(async (taskArgs, hre) => {
  const { deployments, ethers } = hre;

  const [deployer] = await ethers.getSigners();

  const UntangledReceiver = await ethers.getContractFactory('UntangledReceiver');
  const untangledReceiver = await deployments.get('UntangledReceiver');
  const untangledReceiverContract = await UntangledReceiver.attach(untangledReceiver.address);

  const result = await untangledReceiverContract.getLastReceivedMessageDetails();
  console.log(result);

  const failedMessageDataGroup = await untangledReceiverContract.failedMessageDataGroup(
    '0x56859070da9e222a3f85a08d4c199cd20a351aa4d51160fffef32eb705964522'
  );

  console.log(failedMessageDataGroup);
});
