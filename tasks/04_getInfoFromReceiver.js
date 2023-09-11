const { networks } = require('../networks');

task('get-info-receiver', 'Get info from receiver').setAction(async (taskArgs, hre) => {
  const { deployments, ethers } = hre;

  const [deployer] = await ethers.getSigners();

  const UntangledReceiver = await ethers.getContractFactory('UntangledReceiver');
  const untangledReceiver = await deployments.get('UntangledReceiver');
  const untangledReceiverContract = await UntangledReceiver.attach(untangledReceiver.address);

  const result = await untangledReceiverContract.getLastReceivedMessageDetails();
  console.log(result);
});
