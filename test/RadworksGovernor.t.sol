// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20VotesComp} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20VotesComp.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IGovernorAlpha} from "src/interfaces/IGovernorAlpha.sol";
import {RadworksGovernorTest} from "test/helpers/RadworksGovernorTest.sol";
import {ProposalTest} from "test/helpers/ProposalTest.sol";

abstract contract Constructor is RadworksGovernorTest {
  function testFuzz_CorrectlySetsAllConstructorArgs(uint256 _blockNumber) public {
    assertEq(governorBravo.name(), "Radworks Governor Bravo");
    assertEq(address(governorBravo.token()), RAD_TOKEN);

    assertEq(governorBravo.votingDelay(), INITIAL_VOTING_DELAY);
    assertLt(governorBravo.votingDelay(), MAX_REASONABLE_TIME_PERIOD);

    assertEq(governorBravo.votingPeriod(), INITIAL_VOTING_PERIOD);
    assertLt(governorBravo.votingPeriod(), MAX_REASONABLE_TIME_PERIOD);

    assertEq(governorBravo.proposalThreshold(), INITIAL_PROPOSAL_THRESHOLD);

    assertEq(governorBravo.quorum(_blockNumber), QUORUM);
    assertEq(governorBravo.timelock(), TIMELOCK);
    assertEq(governorBravo.COUNTING_MODE(), "support=bravo&quorum=bravo");
  }
}

abstract contract Propose is ProposalTest {
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
    uint256 _newProposalThreshold
  ) public {
    vm.assume(_newDelay != governorBravo.votingDelay());
    vm.assume(_newVotingPeriod != governorBravo.votingPeriod());
    vm.assume(_newProposalThreshold != governorBravo.proposalThreshold());

    // The upper bounds are arbitrary here.
    _newDelay = bound(_newDelay, 0, 50_000); // about a week at 1 block per 12s
    _newVotingPeriod = bound(_newVotingPeriod, 1, 200_000); // about a month
    _newProposalThreshold = bound(_newProposalThreshold, 0, 42 ether);

    _upgradeToBravoGovernor();

    address[] memory _targets = new address[](3);
    uint256[] memory _values = new uint256[](3);
    bytes[] memory _calldatas = new bytes[](3);
    string memory _description = "Update governance settings";

    _targets[0] = address(governorBravo);
    _calldatas[0] = _buildProposalData("setVotingDelay(uint256)", abi.encode(_newDelay));

    _targets[1] = address(governorBravo);
    _calldatas[1] = _buildProposalData("setVotingPeriod(uint256)", abi.encode(_newVotingPeriod));

    _targets[2] = address(governorBravo);
    _calldatas[2] =
      _buildProposalData("setProposalThreshold(uint256)", abi.encode(_newProposalThreshold));

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

    // Confirm that governance settings have updated.
    assertEq(governorBravo.votingDelay(), _newDelay);
    assertEq(governorBravo.votingPeriod(), _newVotingPeriod);
    assertEq(governorBravo.proposalThreshold(), _newProposalThreshold);
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
