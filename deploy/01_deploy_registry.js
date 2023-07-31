const deployProxy = require('../utils/deployHelper');

// async function app () {
//   console.log(4, await deployProxy.deployProxy());
// }

// app().then(() => console.log('done calling app()'));
// console.log(8, await deployProxy)
module.exports = async ({ getNamedAccounts, deployments }) => {
  // console.log(4, getNamedAccounts, deployments)
  await deployProxy({ getNamedAccounts, deployments }, 'Registry', []);
};

module.exports.tags = ['registry'];
