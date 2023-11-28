// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20VotesComp} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20VotesComp.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IGovernorAlpha} from "src/interfaces/IGovernorAlpha.sol";
import {RadworksGovernorTest} from "test/helpers/RadworksGovernorTest.sol";
import {ProposalTest} from "test/helpers/ProposalTest.sol";

abstract contract RadworksDripsGovernance is ProposalTest {
  function setUp() public virtual override(ProposalTest) {
    ProposalTest.setUp();
    _upgradeToBravoGovernor();
  }

  function _proposePassAndExecuteDripsProposal(string memory _description, bytes memory _callData)
    internal
  {
    address[] memory _targets = new address[](1);
    uint256[] memory _values = new uint256[](1);
    bytes[] memory _calldatas = new bytes[](1);

    _targets[0] = DRIPS;
    _calldatas[0] = _callData;

    // Submit the new proposal
    vm.prank(PROPOSER);
    uint256 _newProposalId = governorBravo.propose(_targets, _values, _calldatas, _description);

    // Ensure proposal is in the expected state
    IGovernor.ProposalState _state = governorBravo.state(_newProposalId);
    assertEq(_state, IGovernor.ProposalState.Pending);

    _jumpToActiveProposal(_newProposalId);

    _delegatesCastVoteOnBravoGovernor(_newProposalId, FOR);
    _jumpToVotingComplete(_newProposalId);

    // Ensure the proposal has succeeded
    _state = governorBravo.state(_newProposalId);
    assertEq(_state, IGovernor.ProposalState.Succeeded);

    // Queue the proposal
    governorBravo.queue(_targets, _values, _calldatas, keccak256(bytes(_description)));

    // Ensure the proposal is queued
    _state = governorBravo.state(_newProposalId);
    assertEq(_state, IGovernor.ProposalState.Queued);

    _jumpPastProposalEta(_newProposalId);

    // Execute the proposal
    governorBravo.execute(_targets, _values, _calldatas, keccak256(bytes(_description)));

    // Ensure the proposal is executed
    _state = governorBravo.state(_newProposalId);
    assertEq(_state, IGovernor.ProposalState.Executed);
  }

  function _grantNewPauserViaGovernance(address _newPauser) internal {
    _proposePassAndExecuteDripsProposal(
      "Grant Pauser role to an address",
      _buildProposalData("grantPauser(address)", abi.encode(_newPauser))
    );
  }

  function _revokePauserViaGovernance(address _newPauser) internal {
    _proposePassAndExecuteDripsProposal(
      "Revoke Pauser role from an address",
      _buildProposalData("revokePauser(address)", abi.encode(_newPauser))
    );
  }

  function testFuzz_grantPauserOnDrips(address _newPauser) public {
    assummeNotTimelock(_newPauser);
    address[] memory _originalPausers = drips.allPausers();

    _grantNewPauserViaGovernance(_newPauser);

    // Ensure the new pauser has been granted pauser role
    assertEq(drips.isPauser(_newPauser), true);

    // Ensure the the list of pausers got longer by 1
    assertEq(_originalPausers.length + 1, drips.allPausers().length);

    // Ensure the new pauser can pause the DRIPS protocol
    vm.prank(_newPauser);
    drips.pause();
    assertTrue(drips.isPaused());

    // Ensure the new pauser can un-pause the DRIPS protocol
    vm.prank(_newPauser);
    drips.unpause();
    assertFalse(drips.isPaused());
  }

  function testFuzz_revokePauserOnDrips(address _newPauser) public {
    assummeNotTimelock(_newPauser);
    _grantNewPauserViaGovernance(_newPauser);

    // Ensure the new pauser has been granted pauser role
    assertEq(drips.isPauser(_newPauser), true);

    _revokePauserViaGovernance(_newPauser);

    // Ensure the new pauser has subsequently had pauser role revoked
    assertEq(drips.isPauser(_newPauser), false);

    // Ensure the newly-revoked pauser cannot pause the DRIPS protocol
    vm.prank(_newPauser);
    vm.expectRevert("Caller not the admin or a pauser");
    drips.pause();
  }

  function test_renounceAdminViaGovernance() public {
    _proposePassAndExecuteDripsProposal(
      "Renounce Admin role", _buildProposalData("renounceAdmin()", abi.encode())
    );

    // Ensure the admin role has been renounced
    assertEq(drips.admin(), address(0));
  }
}

contract _ExecuteTestWithDeployScriptGovernor is RadworksDripsGovernance {
  function _useDeployedGovernorBravo() internal pure override returns (bool) {
    return false;
  }
}
