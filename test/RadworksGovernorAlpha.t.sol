// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20VotesComp} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20VotesComp.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IGovernorAlpha} from "src/interfaces/IGovernorAlpha.sol";
import {RadworksGovernorTest} from "test/helpers/RadworksGovernorTest.sol";
import {ProposalTest} from "test/helpers/ProposalTest.sol";

abstract contract RadworksGovernorAlphaTest is ProposalTest {
  function test_GovernorUpgradeProposalIsSubmittedCorrectly() public {
    // Proposal has been recorded
    assertEq(governorAlpha.proposalCount(), initialProposalCount + 1);

    // Proposal is in the expected state
    uint8 _state = governorAlpha.state(upgradeProposalId);
    assertEq(_state, PENDING);

    // Proposal actions correspond to Governor upgrade
    (
      address[] memory _targets,
      uint256[] memory _values,
      string[] memory _signatures,
      bytes[] memory _calldatas
    ) = governorAlpha.getActions(upgradeProposalId);
    assertEq(_targets.length, 3);
    assertEq(_targets[0], RAD_TOKEN);
    assertEq(_targets[1], TIMELOCK);
    assertEq(_targets[2], address(governorBravo));
    assertEq(_values.length, 3);
    assertEq(_values[0], 0);
    assertEq(_values[1], 0);
    assertEq(_values[2], 0);
    assertEq(_signatures.length, 3);
    assertEq(_signatures[0], "transfer(address,uint256)");
    assertEq(_signatures[1], "setPendingAdmin(address)");
    assertEq(_signatures[2], "__acceptAdmin()");
    assertEq(_calldatas.length, 3);
    assertEq(_calldatas[0], abi.encode(SCOPELIFT_ADDRESS, SCOPELIFT_PAYMENT));
    assertEq(_calldatas[1], abi.encode(address(governorBravo)));
    assertEq(_calldatas[2], "");
  }

  function test_UpgradeProposalActiveAfterDelay() public {
    _jumpToActiveUpgradeProposal();

    // Ensure proposal has become active the block after the voting delay
    uint8 _state = governorAlpha.state(upgradeProposalId);
    assertEq(_state, ACTIVE);
  }

  function testFuzz_UpgradeProposerCanCastVote(bool _willSupport) public {
    _jumpToActiveUpgradeProposal();
    uint256 _proposerVotes =
      ERC20VotesComp(RAD_TOKEN).getPriorVotes(PROPOSER, _upgradeProposalStartBlock());

    vm.prank(PROPOSER);
    governorAlpha.castVote(upgradeProposalId, _willSupport);

    IGovernorAlpha.Receipt memory _receipt = governorAlpha.getReceipt(upgradeProposalId, PROPOSER);
    assertEq(_receipt.hasVoted, true);
    assertEq(_receipt.support, _willSupport);
    assertEq(_receipt.votes, _proposerVotes);
  }

  function test_UpgradeProposalSucceedsWhenAllDelegatesVoteFor() public {
    _passUpgradeProposal();

    // Ensure proposal state is now succeeded
    uint8 _state = governorAlpha.state(upgradeProposalId);
    assertEq(_state, SUCCEEDED);
  }

  function test_UpgradeProposalDefeatedWhenAllDelegatesVoteAgainst() public {
    _defeatUpgradeProposal();

    // Ensure proposal state is now defeated
    uint8 _state = governorAlpha.state(upgradeProposalId);
    assertEq(_state, DEFEATED);
  }

  function test_UpgradeProposalCanBeQueuedAfterSucceeding() public {
    _passUpgradeProposal();
    governorAlpha.queue(upgradeProposalId);

    // Ensure proposal can be queued after success
    uint8 _state = governorAlpha.state(upgradeProposalId);
    assertEq(_state, QUEUED);

    (
      address[] memory _targets,
      uint256[] memory _values,
      string[] memory _signatures,
      bytes[] memory _calldatas
    ) = governorAlpha.getActions(upgradeProposalId);

    uint256 _eta = block.timestamp + timelock.delay();

    for (uint256 _index = 0; _index < _targets.length; _index++) {
      // Calculate hash of transaction in Timelock
      bytes32 _txHash = keccak256(
        abi.encode(_targets[_index], _values[_index], _signatures[_index], _calldatas[_index], _eta)
      );

      // Ensure transaction is queued in Timelock
      bool _isQueued = timelock.queuedTransactions(_txHash);
      assertEq(_isQueued, true);
    }
  }

  function test_UpgradeProposalCanBeExecutedAfterDelay() public {
    // get the starting Timelock and ScopeLift RAD balances
    uint256 _timelockRADBalance = ERC20VotesComp(RAD_TOKEN).balanceOf(TIMELOCK);
    uint256 _scopeLiftRADBalance = ERC20VotesComp(RAD_TOKEN).balanceOf(SCOPELIFT_ADDRESS);

    _passAndQueueUpgradeProposal();
    _jumpPastProposalEta();

    // Execute the proposal
    governorAlpha.execute(upgradeProposalId);

    // Ensure the proposal is now executed
    uint8 _state = governorAlpha.state(upgradeProposalId);
    assertEq(_state, EXECUTED);

    // Ensure the governorBravo is now the admin of the timelock
    assertEq(timelock.admin(), address(governorBravo));

    // Ensure the Timelock has transferred the RAD tokens to the ScopeLift address
    assertEq(
      ERC20VotesComp(RAD_TOKEN).balanceOf(TIMELOCK),
      _timelockRADBalance - SCOPELIFT_PAYMENT,
      "Timelock RAD balance is incorrect"
    );
    assertEq(
      ERC20VotesComp(RAD_TOKEN).balanceOf(SCOPELIFT_ADDRESS),
      _scopeLiftRADBalance + SCOPELIFT_PAYMENT,
      "ScopeLift RAD balance is incorrect"
    );
  }

  //
  // Post proposal tests
  //
  function testFuzz_OldGovernorSendsETHAfterProposalIsDefeated(uint128 _amount, address _receiver)
    public
  {
    _assumeReceiver(_receiver);

    // Counter-intuitively, the Governor (not the Timelock) must hold the ETH.
    // See the deployed GovernorAlpha, line 281:
    //   https://etherscan.io/address/0x690e775361AD66D1c4A25d89da9fCd639F5198eD#code
    // The governor transfers ETH to the Timelock in the process of executing
    // the proposal. The Timelock then just passes that ETH along.
    vm.deal(address(governorAlpha), _amount);

    uint256 _receiverETHBalance = _receiver.balance;
    uint256 _governorETHBalance = address(governorAlpha).balance;

    // Defeat the proposal to upgrade the Governor
    _defeatUpgradeProposal();

    // Create a new proposal to send the ETH.
    address[] memory _targets = new address[](1);
    uint256[] memory _values = new uint256[](1);
    _targets[0] = _receiver;
    _values[0] = _amount;

    _queueAndVoteAndExecuteProposalWithAlphaGovernor(
      _targets,
      _values,
      new string[](1), // No signature needed for an ETH send.
      new bytes[](1), // No calldata needed for an ETH send.
      true // GovernorAlpha is still the Timelock admin.
    );

    // Ensure the ETH has been transferred to the receiver
    assertEq(
      address(governorAlpha).balance,
      _governorETHBalance - _amount,
      "Governor alpha ETH balance is incorrect"
    );
    assertEq(_receiver.balance, _receiverETHBalance + _amount, "Receiver ETH balance is incorrect");
  }

  function testFuzz_OldGovernorCanNotSendTokensAfterUpgradeCompletes(
    uint256 _amount,
    address _receiver,
    uint256 _seed
  ) public {
    _assumeReceiver(_receiver);
    IERC20 _token = _randomERC20Token(_seed);

    // Pass and execute the proposal to upgrade the Governor
    _upgradeToBravoGovernor();

    uint256 _receiverTokenBalance = _token.balanceOf(_receiver);
    uint256 _timelockTokenBalance = _token.balanceOf(TIMELOCK);
    // bound by the number of tokens the timelock currently controls
    _amount = bound(_amount, 0, _timelockTokenBalance);

    // Craft a new proposal to send the token.
    address[] memory _targets = new address[](1);
    uint256[] memory _values = new uint256[](1);
    string[] memory _signatures = new string[](1);
    bytes[] memory _calldatas = new bytes[](1);

    _targets[0] = address(_token);
    _values[0] = 0;
    _signatures[0] = "transfer(address,uint256)";
    _calldatas[0] = abi.encode(_receiver, _amount);

    _queueAndVoteAndExecuteProposalWithAlphaGovernor(
      _targets,
      _values,
      _signatures,
      _calldatas,
      false // GovernorAlpha is not the Timelock admin anymore.
    );

    // Ensure no tokens have been transferred from the timelock to the receiver.
    assertEq(_token.balanceOf(TIMELOCK), _timelockTokenBalance, "Timelock balance is incorrect");
    assertEq(_token.balanceOf(_receiver), _receiverTokenBalance, "Receiver balance is incorrect");
  }
}

contract RadworksGovernorUpgradeTest is RadworksGovernorAlphaTest {
  function _useDeployedGovernorBravo() internal pure override returns (bool) {
    return false;
  }
}
