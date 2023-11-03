// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

contract DeployInput {
  uint256 constant INITIAL_VOTING_DELAY = 7200; // 24 hours
  uint256 constant INITIAL_VOTING_PERIOD = 28_800; // matches existing config
  uint256 constant INITIAL_PROPOSAL_THRESHOLD = 10_000e18; // matches existing config
}
