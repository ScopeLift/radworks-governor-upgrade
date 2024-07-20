// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

contract DeployInput {
  uint256 constant INITIAL_VOTING_DELAY = 7200; // in blocks; 5 blocks/min * 60 * 24 = 1 day
  uint256 constant INITIAL_VOTING_PERIOD = 17_280; // matches existing config
  uint256 constant INITIAL_PROPOSAL_THRESHOLD = 1_000_000e18; // matches existing config
}
