// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

contract DeployInput {
  uint256 constant INITIAL_VOTING_DELAY = 7200; // 24 hours
  uint256 constant INITIAL_VOTING_PERIOD = 17_280; // matches existing config
  uint256 constant INITIAL_PROPOSAL_THRESHOLD = 1_000_000e18; // matches existing config

  // ScopeLift address for receiving the RAD tokens upon upgrade execution
  address constant SCOPELIFT_ADDRESS = 0x5C04E7808455ee0e22c2773328C151d0DD79dC62;

  // Number of RAD tokens to transfer to ScopeLift upon upgrade execution
  uint256 constant SCOPELIFT_PAYMENT = 5000e18;
}
