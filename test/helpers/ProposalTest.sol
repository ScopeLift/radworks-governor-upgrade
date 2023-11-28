// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {ICompoundTimelock} from
  "@openzeppelin/contracts/governance/extensions/GovernorTimelockCompound.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

import {TestableProposeScript} from "test/helpers/TestableProposeScript.sol";
import {IGovernorAlpha} from "src/interfaces/IGovernorAlpha.sol";
import {IDrips} from "src/interfaces/IDrips.sol";
import {RadworksGovernorTest} from "test/helpers/RadworksGovernorTest.sol";

abstract contract ProposalTest is RadworksGovernorTest {
  //----------------- State and Setup ----------- //

  IDrips drips = IDrips(DRIPS);
  IGovernorAlpha governorAlpha = IGovernorAlpha(GOVERNOR_ALPHA);
  ICompoundTimelock timelock = ICompoundTimelock(payable(TIMELOCK));
  uint256 initialProposalCount;
  uint256 upgradeProposalId;

  // As defined in the GovernorAlpha ProposalState Enum
  uint8 constant PENDING = 0;
  uint8 constant ACTIVE = 1;
  uint8 constant DEFEATED = 3;
  uint8 constant SUCCEEDED = 4;
  uint8 constant QUEUED = 5;
  uint8 constant EXECUTED = 7;

  // From GovernorCountingSimple
  uint8 constant AGAINST = 0;
  uint8 constant FOR = 1;
  uint8 constant ABSTAIN = 2;

  function setUp() public virtual override {
    RadworksGovernorTest.setUp();

    if (_useDeployedGovernorBravo()) {
      // Use the actual live proposal data expected to be on chain
      // if Radworks Governor Bravo has already deployed
      upgradeProposalId = 17; // assume this is the next proposal (as most recent is 16)
      // Since the proposal was already submitted, the count before its submissions is one less
      initialProposalCount = governorAlpha.proposalCount() - 1;
    } else {
      initialProposalCount = governorAlpha.proposalCount();

      TestableProposeScript _proposeScript = new TestableProposeScript();
      // We override the deployer to use an alternate delegate, because in this context,
      // the PROPOSER_ADDRESS used already has a live proposal
      _proposeScript.overrideProposerForTests(0x69dceee155C31eA0c8354F90BDD65C12FaF5A00a);

      upgradeProposalId = _proposeScript.run(governorBravo);
    }
  }

  //--------------- HELPERS ---------------//

  // a cheat for fuzzing addresses that are payable only
  // Why is this no longer in standard cheats? JJF
  // see https://github.com/foundry-rs/foundry/issues/3631
  function assumePayable(address _addr) internal virtual {
    (bool success,) = payable(_addr).call{value: 0}("");
    vm.assume(success);
  }

  function assummeNotTimelock(address _addr) internal virtual {
    vm.assume(
      // We don't want the receiver to be the Timelock, as that would make our
      // assertions less meaningful -- most of our tests want to confirm that
      // proposals can cause tokens to be sent *from* the timelock to somewhere
      // else.
      _addr != TIMELOCK
      // We also can't have the receiver be the zero address because RAD
      // blocks transfers to the zero address -- see line 396:
      // https://etherscan.io/address/0x31c8EAcBFFdD875c74b94b077895Bd78CF1E64A3#code
      && _addr > address(0)
    );
    assumeNoPrecompiles(_addr);
  }

  function _assumeReceiver(address _receiver) internal {
    assumePayable(_receiver);
    assummeNotTimelock(_receiver);
  }

  function _randomERC20Token(uint256 _seed) internal pure returns (IERC20 _token) {
    if (_seed % 5 == 0) _token = IERC20(RAD_TOKEN);
    if (_seed % 5 == 1) _token = IERC20(USDC_ADDRESS);
    if (_seed % 5 == 2) _token = IERC20(GTC_ADDRESS);
    if (_seed % 5 == 3) _token = IERC20(WETH_ADDRESS);
    if (_seed % 5 == 4) _token = IERC20(MTV_ADDRESS);
  }

  function _upgradeProposalStartBlock() internal view returns (uint256) {
    (,, uint256 _startBlock,,,,,) = governorAlpha.proposals(upgradeProposalId);
    return _startBlock;
  }

  function _upgradeProposalEndBlock() internal view returns (uint256) {
    (,,, uint256 _endBlock,,,,) = governorAlpha.proposals(upgradeProposalId);
    return _endBlock;
  }

  function _upgradeProposalEta() internal view returns (uint256) {
    (, uint256 _eta,,,,,,) = governorAlpha.proposals(upgradeProposalId);
    return _eta;
  }

  function _jumpToActiveUpgradeProposal() internal {
    vm.roll(_upgradeProposalStartBlock() + 1);
  }

  function _jumpToUpgradeVoteComplete() internal {
    vm.roll(_upgradeProposalEndBlock() + 1);
  }

  function _jumpPastProposalEta() internal {
    vm.roll(block.number + 1); // move up one block so we're not in the same block as when queued
    vm.warp(_upgradeProposalEta() + 1); // jump past the eta timestamp
  }

  function _delegatesVoteOnUpgradeProposal(bool _support) internal {
    for (uint256 _index = 0; _index < delegates.length; _index++) {
      vm.prank(delegates[_index].addr);
      governorAlpha.castVote(upgradeProposalId, _support);
    }
  }

  function _passUpgradeProposal() internal {
    _jumpToActiveUpgradeProposal();
    _delegatesVoteOnUpgradeProposal(true);
    _jumpToUpgradeVoteComplete();
  }

  function _defeatUpgradeProposal() internal {
    _jumpToActiveUpgradeProposal();
    _delegatesVoteOnUpgradeProposal(false);
    _jumpToUpgradeVoteComplete();
  }

  function _passAndQueueUpgradeProposal() internal {
    _passUpgradeProposal();
    governorAlpha.queue(upgradeProposalId);
  }

  function _upgradeToBravoGovernor() internal {
    _passAndQueueUpgradeProposal();
    _jumpPastProposalEta();
    governorAlpha.execute(upgradeProposalId);
  }

  function _queueAndVoteAndExecuteProposalWithAlphaGovernor(
    address[] memory _targets,
    uint256[] memory _values,
    string[] memory _signatures,
    bytes[] memory _calldatas,
    bool isGovernorAlphaAdmin
  ) internal {
    // Submit the new proposal
    vm.prank(PROPOSER);
    uint256 _newProposalId =
      governorAlpha.propose(_targets, _values, _signatures, _calldatas, "Proposal for old Governor");

    // Pass and execute the new proposal
    (,, uint256 _startBlock, uint256 _endBlock,,,,) = governorAlpha.proposals(_newProposalId);
    vm.roll(_startBlock + 1);
    for (uint256 _index = 0; _index < delegates.length; _index++) {
      vm.prank(delegates[_index].addr);
      governorAlpha.castVote(_newProposalId, true);
    }
    vm.roll(_endBlock + 1);

    if (!isGovernorAlphaAdmin) {
      vm.expectRevert("Timelock::queueTransaction: Call must come from admin.");
      governorAlpha.queue(_newProposalId);
      return;
    }

    governorAlpha.queue(_newProposalId);
    vm.roll(block.number + 1);
    (, uint256 _eta,,,,,,) = governorAlpha.proposals(_newProposalId);
    vm.warp(_eta + 1);

    governorAlpha.execute(_newProposalId);

    // Ensure the new proposal is now executed
    assertEq(governorAlpha.state(_newProposalId), EXECUTED);
  }

  function _buildProposalData(string memory _signature, bytes memory _calldata)
    internal
    pure
    returns (bytes memory)
  {
    return abi.encodePacked(bytes4(keccak256(bytes(_signature))), _calldata);
  }

  function _jumpToActiveProposal(uint256 _proposalId) internal {
    uint256 _snapshot = governorBravo.proposalSnapshot(_proposalId);
    vm.roll(_snapshot + 1);

    // Ensure the proposal is now Active
    IGovernor.ProposalState _state = governorBravo.state(_proposalId);
    assertEq(_state, IGovernor.ProposalState.Active);
  }

  function _jumpToVotingComplete(uint256 _proposalId) internal {
    // Jump one block past the proposal voting deadline
    uint256 _deadline = governorBravo.proposalDeadline(_proposalId);
    vm.roll(_deadline + 1);
  }

  function _jumpPastProposalEta(uint256 _proposalId) internal {
    uint256 _eta = governorBravo.proposalEta(_proposalId);
    vm.roll(block.number + 1);
    vm.warp(_eta + 1);
  }

  function _delegatesCastVoteOnBravoGovernor(uint256 _proposalId, uint8 _support) internal {
    require(_support < 3, "Invalid value for support");

    for (uint256 _index = 0; _index < delegates.length; _index++) {
      vm.prank(delegates[_index].addr);
      governorBravo.castVote(_proposalId, _support);
    }
  }

  function _buildTokenSendProposal(address _token, uint256 _tokenAmount, address _receiver)
    internal
    pure
    returns (
      address[] memory _targets,
      uint256[] memory _values,
      bytes[] memory _calldata,
      string memory _description
    )
  {
    // Craft a new proposal to send _token.
    _targets = new address[](1);
    _values = new uint256[](1);
    _calldata = new bytes[](1);

    _targets[0] = _token;
    _values[0] = 0;
    _calldata[0] =
      _buildProposalData("transfer(address,uint256)", abi.encode(_receiver, _tokenAmount));
    _description = "Transfer some tokens from the new Governor";
  }

  function _submitTokenSendProposalToGovernorBravo(
    address _token,
    uint256 _amount,
    address _receiver
  )
    internal
    returns (
      uint256 _newProposalId,
      address[] memory _targets,
      uint256[] memory _values,
      bytes[] memory _calldata,
      string memory _description
    )
  {
    (_targets, _values, _calldata, _description) =
      _buildTokenSendProposal(_token, _amount, _receiver);

    // Submit the new proposal
    vm.prank(PROPOSER);
    _newProposalId = governorBravo.propose(_targets, _values, _calldata, _description);

    // Ensure proposal is in the expected state
    IGovernor.ProposalState _state = governorBravo.state(_newProposalId);
    assertEq(_state, IGovernor.ProposalState.Pending);
  }

  // Take a proposal through its full lifecycle, from proposing it, to voting on
  // it, to queuing it, to executing it (if relevant) via GovernorBravo.
  function _queueAndVoteAndExecuteProposalWithBravoGovernor(
    address[] memory _targets,
    uint256[] memory _values,
    bytes[] memory _calldatas,
    string memory _description,
    uint8 _voteType
  ) internal {
    // Submit the new proposal
    vm.prank(PROPOSER);
    uint256 _newProposalId = governorBravo.propose(_targets, _values, _calldatas, _description);

    // Ensure proposal is Pending.
    IGovernor.ProposalState _state = governorBravo.state(_newProposalId);
    assertEq(_state, IGovernor.ProposalState.Pending);

    _jumpToActiveProposal(_newProposalId);

    // Have all delegates cast their weight with the specified support type.
    _delegatesCastVoteOnBravoGovernor(_newProposalId, _voteType);

    _jumpToVotingComplete(_newProposalId);

    _state = governorBravo.state(_newProposalId);
    if (_voteType == AGAINST || _voteType == ABSTAIN) {
      // The proposal should have failed.
      assertEq(_state, IGovernor.ProposalState.Defeated);

      // Attempt to queue the proposal.
      vm.expectRevert("Governor: proposal not successful");
      governorBravo.queue(_targets, _values, _calldatas, keccak256(bytes(_description)));

      _jumpPastProposalEta(_newProposalId);

      // Attempt to execute the proposal.
      vm.expectRevert("Governor: proposal not successful");
      governorBravo.execute(_targets, _values, _calldatas, keccak256(bytes(_description)));

      // Exit this function, there's nothing left to test.
      return;
    }

    // The voteType was FOR. Ensure the proposal has succeeded.
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

  function assertEq(IGovernor.ProposalState _actual, IGovernor.ProposalState _expected) internal {
    assertEq(uint8(_actual), uint8(_expected));
  }
}
