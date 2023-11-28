// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

contract Constants {
  address constant GOVERNOR_ALPHA = 0x690e775361AD66D1c4A25d89da9fCd639F5198eD;
  address payable constant RAD_TOKEN = payable(0x31c8EAcBFFdD875c74b94b077895Bd78CF1E64A3);
  address constant TIMELOCK = 0x8dA8f82d2BbDd896822de723F55D6EdF416130ba;
  address constant DRIPS = 0xd0Dd053392db676D57317CD4fe96Fc2cCf42D0b4;

  // TODO: resolve the list of large delegates with tallyaddress
  address constant PROPOSER = 0x464D78a5C97A2E2E9839C353ee9B6d4204c90B0b; // cloudhead.eth

  address constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  address constant GTC_ADDRESS = 0xDe30da39c46104798bB5aA3fe8B9e0e1F348163F;
  address constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address constant MTV_ADDRESS = 0x6226e00bCAc68b0Fe55583B90A1d727C14fAB77f;
  uint256 constant MAX_REASONABLE_TIME_PERIOD = 302_400; // 6 weeks assume a 12 sec block time

  // we have not yet deployed the Radworks Bravo Governor
  address constant DEPLOYED_BRAVO_GOVERNOR = 0x1111111111111111111111111111111111111111;

  uint256 constant QUORUM = 4_000_000e18;
}
