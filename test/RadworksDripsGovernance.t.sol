// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {ProposalTest} from "test/helpers/ProposalTest.sol";

abstract contract RadworksDripsGovernance is ProposalTest {
  function setUp() public virtual override(ProposalTest) {
    ProposalTest.setUp();
    _upgradeToBravoGovernor();
  }

  function _grantNewPauserViaGovernance(address _newPauser) internal {
    (
      address[] memory _targets,
      uint256[] memory _values,
      bytes[] memory _calldatas,
      string memory _description
    ) = _buildDripsGovernanceProposal(
      "Grant Pauser role to an address",
      _buildProposalData("grantPauser(address)", abi.encode(_newPauser))
    );
    _queueAndVoteAndExecuteProposalWithBravoGovernor(
      _targets, _values, _calldatas, _description, FOR
    );
  }

  function _revokePauserViaGovernance(address _newPauser) internal {
    (
      address[] memory _targets,
      uint256[] memory _values,
      bytes[] memory _calldatas,
      string memory _description
    ) = _buildDripsGovernanceProposal(
      "Revoke Pauser role from an address",
      _buildProposalData("revokePauser(address)", abi.encode(_newPauser))
    );
    _queueAndVoteAndExecuteProposalWithBravoGovernor(
      _targets, _values, _calldatas, _description, FOR
    );
  }

  function testFuzz_grantPauserOnDrips(address _newPauser) public {
    _assumeNotTimelock(_newPauser);
    vm.assume(!drips.isPauser(_newPauser));
    address[] memory _originalPausers = drips.allPausers();

    _grantNewPauserViaGovernance(_newPauser);

    // Ensure the new pauser has been granted pauser role
    assertEq(drips.isPauser(_newPauser), true);

    // Ensure the the list of pausers got longer by 1
    assertEq(_originalPausers.length + 1, drips.allPausers().length);
  }

  function testFuzz_grantedPauserCanPauseAndUnPause(address _newPauser) public {
    _assumeNotTimelock(_newPauser);

    _grantNewPauserViaGovernance(_newPauser);

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
    _assumeNotTimelock(_newPauser);
    _grantNewPauserViaGovernance(_newPauser);

    // Ensure the new pauser has been granted pauser role
    assertEq(drips.isPauser(_newPauser), true);

    _revokePauserViaGovernance(_newPauser);

    // Ensure the new pauser has subsequently had pauser role revoked
    assertEq(drips.isPauser(_newPauser), false);
  }

  function testFuzz_revertWhenRevokedPauserAttemptsPause(address _newPauser) public {
    _assumeNotTimelock(_newPauser);
    _grantNewPauserViaGovernance(_newPauser);

    // Ensure the new pauser has been granted pauser role
    assertEq(drips.isPauser(_newPauser), true);

    _revokePauserViaGovernance(_newPauser);

    // Ensure the newly-revoked pauser cannot pause the DRIPS protocol
    vm.prank(_newPauser);
    vm.expectRevert("Caller not the admin or a pauser");
    drips.pause();

    // Ensure that the Timelock contract is can still pause the DRIPS protocol
    vm.prank(TIMELOCK);
    drips.pause();
    assertEq(drips.isPauser(_newPauser), false);
  }

  function test_renounceAdminViaGovernance() public {
    (
      address[] memory _targets,
      uint256[] memory _values,
      bytes[] memory _calldatas,
      string memory _description
    ) = _buildDripsGovernanceProposal(
      "Renounce Admin role", _buildProposalData("renounceAdmin()", abi.encode())
    );
    _queueAndVoteAndExecuteProposalWithBravoGovernor(
      _targets, _values, _calldatas, _description, FOR
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
