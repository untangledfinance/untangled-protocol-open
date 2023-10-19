const { utils } = require("ethers");


const POOL_ADMIN_ROLE = utils.keccak256(Buffer.from("POOL_CREATOR"));


module.exports = {
  POOL_ADMIN_ROLE
};