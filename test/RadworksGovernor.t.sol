// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20VotesComp} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20VotesComp.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IGovernorAlpha} from "src/interfaces/IGovernorAlpha.sol";
import {RadworksGovernorTest} from "test/helpers/RadworksGovernorTest.sol";
import {ProposalTest} from "test/helpers/ProposalTest.sol";
import {ProposalBuilder} from "test/helpers/Proposal.sol";
import "../script/DeployInput.sol";

abstract contract Constructor is RadworksGovernorTest {
  function test_CorrectlySetsAllConstructorArgs() public {
    assertEq(governorBravo.name(), "Radworks Governor Bravo");
    assertEq(address(governorBravo.token()), RAD_TOKEN);

    assertEq(governorBravo.votingDelay(), INITIAL_VOTING_DELAY);
    assertLt(governorBravo.votingDelay(), MAX_REASONABLE_TIME_PERIOD);

    assertEq(governorBravo.votingPeriod(), INITIAL_VOTING_PERIOD);
    assertLt(governorBravo.votingPeriod(), MAX_REASONABLE_TIME_PERIOD);

    assertEq(governorBravo.proposalThreshold(), INITIAL_PROPOSAL_THRESHOLD);

    assertEq(governorBravo.quorum(block.number), INITIAL_QUORUM_VALUE);
    assertEq(governorBravo.timelock(), TIMELOCK);
    assertEq(governorBravo.COUNTING_MODE(), "support=bravo&quorum=bravo");
  }
}

abstract contract Propose is ProposalTest {
  event QuorumSet(uint256 newQuorum);

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
    assertEq(_targets.length, 2);
    assertEq(_targets[0], TIMELOCK);
    assertEq(_targets[1], address(governorBravo));
    assertEq(_values.length, 2);
    assertEq(_values[0], 0);
    assertEq(_values[1], 0);
    assertEq(_signatures.length, 2);
    assertEq(_signatures[0], "setPendingAdmin(address)");
    assertEq(_signatures[1], "__acceptAdmin()");
    assertEq(_calldatas.length, 2);
    assertEq(_calldatas[0], abi.encode(address(governorBravo)));
    assertEq(_calldatas[1], "");
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
    _passAndQueueUpgradeProposal();
    _jumpPastProposalEta();

    // Execute the proposal
    governorAlpha.execute(upgradeProposalId);

    // Ensure the proposal is now executed
    uint8 _state = governorAlpha.state(upgradeProposalId);
    assertEq(_state, EXECUTED);

    // Ensure the governorBravo is now the admin of the timelock
    assertEq(timelock.admin(), address(governorBravo));
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
    //   https://etherscan.io/address/0x31c8EAcBFFdD875c74b94b077895Bd78CF1E64A3#code
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

    uint256 _receiverTokenBalance = _token.balanceOf(_receiver);
    uint256 _timelockTokenBalance = _token.balanceOf(TIMELOCK);
    // bound by the number of tokens the timelock currently controls
    _amount = bound(_amount, 0, _timelockTokenBalance);

    // Pass and execute the proposal to upgrade the Governor
    _upgradeToBravoGovernor();

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

  //
  // Bravo proposal tests
  //
  function testFuzz_NewGovernorCanReceiveNewProposal(uint256 _amount, address _receiver) public {
    _assumeReceiver(_receiver);
    _upgradeToBravoGovernor();
    _submitTokenSendProposalToGovernorBravo(RAD_TOKEN, _amount, _receiver);
  }

  function testFuzz_NewGovernorCanDefeatProposal(uint256 _amount, address _receiver, uint256 _seed)
    public
  {
    IERC20 _token = _randomERC20Token(_seed);
    _assumeReceiver(_receiver);

    _upgradeToBravoGovernor();

    (
      address[] memory _targets,
      uint256[] memory _values,
      bytes[] memory _calldatas,
      string memory _description
    ) = _buildTokenSendProposal(address(_token), _amount, _receiver);

    _queueAndVoteAndExecuteProposalWithBravoGovernor(
      _targets,
      _values,
      _calldatas,
      _description,
      (_amount % 2 == 1 ? AGAINST : ABSTAIN) // Randomize vote type.
    );

    // It should not be possible to queue the proposal
    vm.expectRevert("Governor: proposal not successful");
    governorBravo.queue(_targets, _values, _calldatas, keccak256(bytes(_description)));
  }

  function testFuzz_NewGovernorCanPassProposalToSendToken(
    uint256 _amount,
    address _receiver,
    uint256 _seed
  ) public {
    IERC20 _token = _randomERC20Token(_seed);
    _assumeReceiver(_receiver);
    uint256 _timelockTokenBalance = _token.balanceOf(TIMELOCK);

    // bound by the number of tokens the timelock currently controls
    _amount = bound(_amount, 0, _timelockTokenBalance);
    uint256 _initialTokenBalance = _token.balanceOf(_receiver);

    _upgradeToBravoGovernor();

    (
      address[] memory _targets,
      uint256[] memory _values,
      bytes[] memory _calldatas,
      string memory _description
    ) = _buildTokenSendProposal(address(_token), _amount, _receiver);

    _queueAndVoteAndExecuteProposalWithBravoGovernor(
      _targets, _values, _calldatas, _description, FOR
    );

    // Ensure the tokens have been transferred
    assertEq(_token.balanceOf(_receiver), _initialTokenBalance + _amount);
    assertEq(_token.balanceOf(TIMELOCK), _timelockTokenBalance - _amount);
  }

  function testFuzz_NewGovernorCanPassProposalToSendETH(uint256 _amount, address _receiver) public {
    _assumeReceiver(_receiver);
    vm.deal(TIMELOCK, _amount);
    uint256 _timelockETHBalance = TIMELOCK.balance;
    uint256 _receiverETHBalance = _receiver.balance;

    _upgradeToBravoGovernor();

    // Craft a new proposal to send ETH.
    address[] memory _targets = new address[](1);
    uint256[] memory _values = new uint256[](1);
    _targets[0] = _receiver;
    _values[0] = _amount;

    _queueAndVoteAndExecuteProposalWithBravoGovernor(
      _targets,
      _values,
      new bytes[](1), // There is no calldata for a plain ETH call.
      "Transfer some ETH via the new Governor",
      FOR // Vote/suppport type.
    );

    // Ensure the ETH was transferred.
    assertEq(_receiver.balance, _receiverETHBalance + _amount);
    assertEq(TIMELOCK.balance, _timelockETHBalance - _amount);
  }

  function testFuzz_NewGovernorCanPassProposalToSendETHWithTokens(
    uint256 _amountETH,
    uint256 _amountToken,
    address _receiver,
    uint256 _seed
  ) public {
    IERC20 _token = _randomERC20Token(_seed);
    _assumeReceiver(_receiver);

    vm.deal(TIMELOCK, _amountETH);
    uint256 _timelockETHBalance = TIMELOCK.balance;
    uint256 _receiverETHBalance = _receiver.balance;

    // Bound _amountToken by the number of tokens the timelock currently controls.
    uint256 _timelockTokenBalance = _token.balanceOf(TIMELOCK);
    uint256 _receiverTokenBalance = _token.balanceOf(_receiver);
    _amountToken = bound(_amountToken, 0, _timelockTokenBalance);

    _upgradeToBravoGovernor();

    // Craft a new proposal to send ETH and tokens.
    address[] memory _targets = new address[](2);
    uint256[] memory _values = new uint256[](2);
    bytes[] memory _calldatas = new bytes[](2);

    // First call transfers tokens.
    _targets[0] = address(_token);
    _calldatas[0] =
      _buildProposalData("transfer(address,uint256)", abi.encode(_receiver, _amountToken));

    // Second call sends ETH.
    _targets[1] = _receiver;
    _values[1] = _amountETH;

    _queueAndVoteAndExecuteProposalWithBravoGovernor(
      _targets,
      _values,
      _calldatas,
      "Transfer tokens and ETH via the new Governor",
      FOR // Vote/suppport type.
    );

    // Ensure the ETH was transferred.
    assertEq(_receiver.balance, _receiverETHBalance + _amountETH);
    assertEq(TIMELOCK.balance, _timelockETHBalance - _amountETH);

    // Ensure the tokens were transferred.
    assertEq(_token.balanceOf(_receiver), _receiverTokenBalance + _amountToken);
    assertEq(_token.balanceOf(TIMELOCK), _timelockTokenBalance - _amountToken);
  }

  function testFuzz_NewGovernorFailedProposalsCantSendETH(uint256 _amount, address _receiver)
    public
  {
    _assumeReceiver(_receiver);
    vm.deal(TIMELOCK, _amount);
    uint256 _timelockETHBalance = TIMELOCK.balance;
    uint256 _receiverETHBalance = _receiver.balance;

    _upgradeToBravoGovernor();

    // Craft a new proposal to send ETH.
    address[] memory _targets = new address[](1);
    uint256[] memory _values = new uint256[](1);
    _targets[0] = _receiver;
    _values[0] = _amount;

    _queueAndVoteAndExecuteProposalWithBravoGovernor(
      _targets,
      _values,
      new bytes[](1), // There is no calldata for a plain ETH call.
      "Transfer some ETH via the new Governor",
      (_amount % 2 == 1 ? AGAINST : ABSTAIN) // Randomize vote type.
    );

    // Ensure ETH was *not* transferred.
    assertEq(_receiver.balance, _receiverETHBalance);
    assertEq(TIMELOCK.balance, _timelockETHBalance);
  }

  function testFuzz_NewGovernorCanUpdateSettingsViaSuccessfulProposal(
    uint256 _newDelay,
    uint256 _newVotingPeriod,
    uint256 _newProposalThreshold,
    uint256 _newQuorumValue
  ) public {
    vm.assume(_newDelay != governorBravo.votingDelay());
    vm.assume(_newVotingPeriod != governorBravo.votingPeriod());
    vm.assume(_newProposalThreshold != governorBravo.proposalThreshold());
    vm.assume(_newQuorumValue != governorBravo.quorum(block.number));

    // The upper bounds are arbitrary here.
    _newDelay = bound(_newDelay, 0, 50_000); // about a week at 1 block per 12s
    _newVotingPeriod = bound(_newVotingPeriod, 1, 200_000); // about a month
    _newProposalThreshold = bound(_newProposalThreshold, 0, 42 ether);
    _newQuorumValue = bound(_newQuorumValue, INITIAL_QUORUM_VALUE / 2, INITIAL_QUORUM_VALUE / 2);

    _upgradeToBravoGovernor();

    address[] memory _targets = new address[](4);
    uint256[] memory _values = new uint256[](4);
    bytes[] memory _calldatas = new bytes[](4);
    string memory _description = "Update governance settings";

    _targets[0] = address(governorBravo);
    _calldatas[0] = _buildProposalData("setVotingDelay(uint256)", abi.encode(_newDelay));

    _targets[1] = address(governorBravo);
    _calldatas[1] = _buildProposalData("setVotingPeriod(uint256)", abi.encode(_newVotingPeriod));

    _targets[2] = address(governorBravo);
    _calldatas[2] =
      _buildProposalData("setProposalThreshold(uint256)", abi.encode(_newProposalThreshold));

    _targets[3] = address(governorBravo);
    _calldatas[3] = _buildProposalData("setQuorum(uint256)", abi.encode(_newQuorumValue));

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

    // Execute the proposal, expecting the emit of the QuorumSet event.
    vm.expectEmit(false, false, false, true);
    emit QuorumSet(_newQuorumValue);
    governorBravo.execute(_targets, _values, _calldatas, keccak256(bytes(_description)));

    // Ensure the proposal is executed
    _state = governorBravo.state(_newProposalId);
    assertEq(_state, IGovernor.ProposalState.Executed);

    // Confirm that governance settings have updated.
    assertEq(governorBravo.votingDelay(), _newDelay);
    assertEq(governorBravo.votingPeriod(), _newVotingPeriod);
    assertEq(governorBravo.proposalThreshold(), _newProposalThreshold);
    assertEq(governorBravo.quorum(block.number), _newQuorumValue);
  }

  function testFuzz_NewGovernorCanPassMixedProposal(
    uint256 _amount,
    address _receiver,
    uint256 _seed
  ) public {
    IERC20 _token = _randomERC20Token(_seed);
    _assumeReceiver(_receiver);
    uint256 _timelockTokenBalance = _token.balanceOf(TIMELOCK);

    // bound by the number of tokens the timelock currently controls
    _amount = bound(_amount, 0, _timelockTokenBalance);
    uint256 _initialTokenBalance = _token.balanceOf(_receiver);

    _upgradeToBravoGovernor();
    (
      uint256 _newProposalId,
      address[] memory _targets,
      uint256[] memory _values,
      bytes[] memory _calldatas,
      string memory _description
    ) = _submitTokenSendProposalToGovernorBravo(address(_token), _amount, _receiver);

    _jumpToActiveProposal(_newProposalId);

    // Delegates vote with a mix of For/Against/Abstain with For winning.
    // TODO: Need more delegates for this.. pool together had more!
    vm.prank(delegates[0].addr);
    governorBravo.castVote(_newProposalId, FOR);
    vm.prank(delegates[1].addr);
    governorBravo.castVote(_newProposalId, FOR);
    vm.prank(delegates[2].addr);
    governorBravo.castVote(_newProposalId, FOR);
    vm.prank(delegates[3].addr);
    governorBravo.castVote(_newProposalId, AGAINST);
    vm.prank(delegates[4].addr);
    governorBravo.castVote(_newProposalId, ABSTAIN);
    vm.prank(delegates[5].addr);
    governorBravo.castVote(_newProposalId, AGAINST);

    // The vote should pass. We are asserting against the raw delegate voting
    // weight as a sanity check. In the event that the fork block is changed and
    // voting weights are materially different than they were when the test was
    // written, we want this assertion to fail.
    assertGt(
      delegates[0].votes + delegates[1].votes + delegates[2].votes, // FOR votes.
      delegates[3].votes + delegates[5].votes // AGAINST votes.
    );

    _jumpToVotingComplete(_newProposalId);

    // Ensure the proposal has succeeded
    IGovernor.ProposalState _state = governorBravo.state(_newProposalId);
    assertEq(_state, IGovernor.ProposalState.Succeeded);

    // Queue the proposal
    governorBravo.queue(_targets, _values, _calldatas, keccak256(bytes(_description)));

    _jumpPastProposalEta(_newProposalId);

    // Execute the proposal
    governorBravo.execute(_targets, _values, _calldatas, keccak256(bytes(_description)));

    // Ensure the proposal is executed
    _state = governorBravo.state(_newProposalId);
    assertEq(_state, IGovernor.ProposalState.Executed);

    // Ensure the tokens have been transferred
    assertEq(_token.balanceOf(_receiver), _initialTokenBalance + _amount);
    assertEq(_token.balanceOf(TIMELOCK), _timelockTokenBalance - _amount);
  }

  function testFuzz_NewGovernorCanDefeatMixedProposal(
    uint256 _amount,
    address _receiver,
    uint256 _seed
  ) public {
    IERC20 _token = _randomERC20Token(_seed);
    _assumeReceiver(_receiver);
    uint256 _timelockTokenBalance = _token.balanceOf(TIMELOCK);

    // bound by the number of tokens the timelock currently controls
    _amount = bound(_amount, 0, _timelockTokenBalance);

    _upgradeToBravoGovernor();

    (
      uint256 _newProposalId,
      address[] memory _targets,
      uint256[] memory _values,
      bytes[] memory _calldatas,
      string memory _description
    ) = _submitTokenSendProposalToGovernorBravo(address(_token), _amount, _receiver);

    _jumpToActiveProposal(_newProposalId);

    // Delegates vote with a mix of For/Against/Abstain with Against/Abstain winning.
    vm.prank(delegates[0].addr);
    governorBravo.castVote(_newProposalId, ABSTAIN);
    vm.prank(delegates[1].addr);
    governorBravo.castVote(_newProposalId, FOR);
    vm.prank(delegates[2].addr);
    governorBravo.castVote(_newProposalId, AGAINST);
    vm.prank(delegates[3].addr);
    governorBravo.castVote(_newProposalId, AGAINST);
    vm.prank(delegates[4].addr);
    governorBravo.castVote(_newProposalId, FOR);
    vm.prank(delegates[5].addr);
    governorBravo.castVote(_newProposalId, AGAINST);

    // The vote should fail. We are asserting against the raw delegate voting
    // weight as a sanity check. In the event that the fork block is changed and
    // voting weights are materially different than they were when the test was
    // written, we want this assertion to fail.
    assertLt(
      delegates[1].votes + delegates[4].votes, // FOR votes.
      delegates[2].votes + delegates[3].votes + delegates[5].votes // AGAINST votes.
    );

    _jumpToVotingComplete(_newProposalId);

    // Ensure the proposal has failed
    IGovernor.ProposalState _state = governorBravo.state(_newProposalId);
    assertEq(_state, IGovernor.ProposalState.Defeated);

    // It should not be possible to queue the proposal
    vm.expectRevert("Governor: proposal not successful");
    governorBravo.queue(_targets, _values, _calldatas, keccak256(bytes(_description)));
  }

  struct NewGovernorUnaffectedByVotesOnOldGovernorVars {
    uint256 alphaProposalId;
    address[] alphaTargets;
    uint256[] alphaValues;
    string[] alphaSignatures;
    bytes[] alphaCalldatas;
    string alphaDescription;
    uint256 bravoProposalId;
    address[] bravoTargets;
    uint256[] bravoValues;
    bytes[] bravoCalldatas;
    string bravoDescription;
  }

  function testFuzz_NewGovernorUnaffectedByVotesOnOldGovernor(
    uint256 _amount,
    address _receiver,
    uint256 _seed
  ) public {
    NewGovernorUnaffectedByVotesOnOldGovernorVars memory _vars;
    IERC20 _token = _randomERC20Token(_seed);
    _assumeReceiver(_receiver);

    _upgradeToBravoGovernor();

    // Create a new proposal to send the token.
    _vars.alphaTargets = new address[](1);
    _vars.alphaValues = new uint256[](1);
    _vars.alphaSignatures = new string[](1);
    _vars.alphaCalldatas = new bytes[](1);
    _vars.alphaDescription = "Transfer some tokens from the new Governor";

    _vars.alphaTargets[0] = address(_token);
    _vars.alphaSignatures[0] = "transfer(address,uint256)";
    _vars.alphaCalldatas[0] = abi.encode(_receiver, _amount);

    // Submit the new proposal to Governor Alpha, which is now deprecated.
    vm.prank(PROPOSER);
    _vars.alphaProposalId = governorAlpha.propose(
      _vars.alphaTargets,
      _vars.alphaValues,
      _vars.alphaSignatures,
      _vars.alphaCalldatas,
      _vars.alphaDescription
    );

    // Now construct and submit an identical proposal on Governor Bravo, which is active.
    (
      _vars.bravoProposalId,
      _vars.bravoTargets,
      _vars.bravoValues,
      _vars.bravoCalldatas,
      _vars.bravoDescription
    ) = _submitTokenSendProposalToGovernorBravo(address(_token), _amount, _receiver);

    assertEq(
      uint8(governorAlpha.state(_vars.alphaProposalId)),
      uint8(governorBravo.state(_vars.bravoProposalId))
    );

    _jumpToActiveProposal(_vars.bravoProposalId);

    // Defeat the proposal on Bravo.
    assertEq(governorBravo.state(_vars.bravoProposalId), IGovernor.ProposalState.Active);
    _delegatesCastVoteOnBravoGovernor(_vars.bravoProposalId, AGAINST);

    // Pass the proposal on Alpha.
    for (uint256 _index = 0; _index < delegates.length; _index++) {
      vm.prank(delegates[_index].addr);
      governorAlpha.castVote(_vars.alphaProposalId, true);
    }

    _jumpToVotingComplete(_vars.bravoProposalId);

    // Ensure the Bravo proposal has failed and Alpha has succeeded.
    assertEq(governorBravo.state(_vars.bravoProposalId), IGovernor.ProposalState.Defeated);
    assertEq(governorAlpha.state(_vars.alphaProposalId), uint8(IGovernor.ProposalState.Succeeded));

    // It should not be possible to queue either proposal, confirming that votes
    // on alpha do not affect votes on bravo.
    vm.expectRevert("Governor: proposal not successful");
    governorBravo.queue(
      _vars.bravoTargets,
      _vars.bravoValues,
      _vars.bravoCalldatas,
      keccak256(bytes(_vars.bravoDescription))
    );
    vm.expectRevert("Timelock::queueTransaction: Call must come from admin.");
    governorAlpha.queue(_vars.alphaProposalId);
  }
}

// TODO: future PR
abstract contract Execute is ProposalTest {}

// Run the tests using the deployed Governor Bravo (future PR)

// Run the tests using a version of the Governor deployed by the Deploy script

contract ConstructorTestWithDeployScriptGovernor is Constructor {
  function _useDeployedGovernorBravo() internal pure override returns (bool) {
    return false;
  }
}

contract ProposeTestWithDeployScriptGovernor is Propose {
  function _useDeployedGovernorBravo() internal pure override returns (bool) {
    return false;
  }
}

// TODO: (future PR)

// contract CastVoteWithReasonAndParamsTestWithDeployScriptGovernor is CastVoteWithReasonAndParams {
//   function _useDeployedGovernorBravo() internal pure override returns (bool) {
//     return false;
//   }
// }

// contract _ExecuteTestWithDeployScriptGovernor is _Execute {
//   function _useDeployedGovernorBravo() internal pure override returns (bool) {
//     return false;
//   }
// }
