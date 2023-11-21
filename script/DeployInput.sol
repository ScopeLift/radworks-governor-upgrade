// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

contract DeployInput {
  uint256 constant INITIAL_VOTING_DELAY = 7200; // 24 hours
  uint256 constant INITIAL_VOTING_PERIOD = 17_280; // matches existing alpha config
  uint256 constant INITIAL_PROPOSAL_THRESHOLD = 1_000_000e18; // matches alpha (1% of total supply)
  uint256 constant INITIAL_QUORUM_VALUE = 4_000_000e18; // matches alpha (4% of total supply)
}
