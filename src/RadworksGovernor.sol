// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {
  ERC20VotesComp,
  GovernorVotesComp
} from "@openzeppelin/contracts/governance/extensions/GovernorVotesComp.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {ICompoundTimelock} from
  "@openzeppelin/contracts/governance/extensions/GovernorTimelockCompound.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";

import {IRadworksTimelock} from "src/interfaces/IRadworksTimelock.sol";
import {RadworksGovernorTimelockCompound} from "src/lib/RadworksGovernorTimelockCompound.sol";
import {GovernorCompatibilityBravo} from
  "@openzeppelin/contracts/governance/compatibility/GovernorCompatibilityBravo.sol";

/// @notice The upgraded Radworks Governor: Bravo compatible and extended from OpenZeppelin.
contract RadworksGovernor is
  Governor,
  GovernorVotesComp,
  RadworksGovernorTimelockCompound,
  GovernorSettings
{
  struct ProposalVote {
    uint256 againstVotes;
    uint256 forVotes;
    uint256 abstainVotes;
  }

  /// @notice The address of the RAD token on Ethereum mainnet from which this Governor derives
  /// delegated voting weight.
  ERC20VotesComp private constant RAD_TOKEN =
    ERC20VotesComp(0x31c8EAcBFFdD875c74b94b077895Bd78CF1E64A3);

  /// @notice The address of the existing Radworks DAO Timelock on Ethereum mainnet through
  /// which this Governor executes transactions.
  IRadworksTimelock private constant TIMELOCK =
    IRadworksTimelock(payable(0x8dA8f82d2BbDd896822de723F55D6EdF416130ba));

  /// @notice Human readable name of this Governor.
  string private constant GOVERNOR_NAME = "Radworks Governor Bravo";

  /// @notice The number of RAD (in "wei") that must participate in a vote for it to meet quorum
  /// threshold.
  ///
  /// TODO: placeholder
  uint256 private constant QUORUM = 100_000e18; // 100,000 RAD

  /// @param _initialVotingDelay The initial voting delay this Governor will enforce.
  /// @param _initialVotingPeriod The initial voting period this Governor will enforce.
  /// @param _initialProposalThreshold The initial number of RAD required to submit
  /// a proposal this Governor will enforce.
  constructor(
    uint256 _initialVotingDelay,
    uint256 _initialVotingPeriod,
    uint256 _initialProposalThreshold
  )
    GovernorVotesComp(RAD_TOKEN)
    GovernorSettings(_initialVotingDelay, _initialVotingPeriod, _initialProposalThreshold)
    RadworksGovernorTimelockCompound(TIMELOCK)
    Governor(GOVERNOR_NAME)
  {}

  /// @dev Mapping from proposal ID to vote tallies for that proposal.
  mapping(uint256 => ProposalVote) private _proposalVotes;

  /// @dev Mapping from proposal ID and address to the weight the address
  /// has cast on that proposal, e.g. _proposalVotersWeightCast[42][0xBEEF]
  /// would tell you the number of votes that 0xBEEF has cast on proposal 42.
  mapping(uint256 => mapping(address => uint256)) private _proposalVotersWeightCast;

  /// @inheritdoc Governor
  function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(Governor, RadworksGovernorTimelockCompound)
    returns (bool)
  {
    return RadworksGovernorTimelockCompound.supportsInterface(interfaceId);
  }

  /// @inheritdoc IGovernor
  // solhint-disable-next-line func-name-mixedcase
  function COUNTING_MODE() public pure override returns (string memory) {
    return "support=bravo&quorum=bravo";
  }

  /// @inheritdoc IGovernor
  function hasVoted(uint256 proposalId, address account)
    public
    view
    virtual
    override
    returns (bool)
  {
    return _proposalVotersWeightCast[proposalId][account] > 0;
  }

  /// @inheritdoc Governor
  function _quorumReached(uint256 proposalId) internal view virtual override returns (bool) {
    ProposalVote storage proposalVote = _proposalVotes[proposalId];

    return quorum(proposalSnapshot(proposalId)) <= proposalVote.forVotes + proposalVote.abstainVotes;
  }

  /// @inheritdoc Governor
  function _voteSucceeded(uint256 proposalId) internal view virtual override returns (bool) {
    ProposalVote storage proposalVote = _proposalVotes[proposalId];

    return proposalVote.forVotes > proposalVote.againstVotes;
  }

  /// @inheritdoc Governor
  function _countVote(
    uint256 proposalId,
    address account,
    uint8 support,
    uint256 weight,
    bytes memory
  ) internal override {
    require(
      _proposalVotersWeightCast[proposalId][account] == 0,
      "Radworks Governor: vote would exceed weight"
    );

    _proposalVotersWeightCast[proposalId][account] = weight;

    if (support == uint8(GovernorCompatibilityBravo.VoteType.Against)) {
      _proposalVotes[proposalId].againstVotes += weight;
    } else if (support == uint8(GovernorCompatibilityBravo.VoteType.For)) {
      _proposalVotes[proposalId].forVotes += weight;
    } else if (support == uint8(GovernorCompatibilityBravo.VoteType.Abstain)) {
      _proposalVotes[proposalId].abstainVotes += weight;
    } else {
      revert("Radworks Governor: invalid support value, must be included in VoteType enum");
    }
  }

  /// @inheritdoc Governor
  function castVoteWithReasonAndParamsBySig(
    uint256 proposalId,
    uint8 support,
    string calldata reason,
    bytes memory params,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) public override(Governor, IGovernor) returns (uint256) {
    return Governor.castVoteWithReasonAndParamsBySig(proposalId, support, reason, params, v, r, s);
  }

  /// @inheritdoc Governor
  function proposalThreshold()
    public
    view
    virtual
    override(Governor, GovernorSettings)
    returns (uint256)
  {
    return GovernorSettings.proposalThreshold();
  }

  /// @inheritdoc Governor
  function state(uint256 proposalId)
    public
    view
    virtual
    override(Governor, RadworksGovernorTimelockCompound)
    returns (ProposalState)
  {
    return RadworksGovernorTimelockCompound.state(proposalId);
  }

  /// @notice The amount of RAD required to meet the quorum threshold for a proposal
  /// as of a given block.
  /// @dev Our implementation ignores the block number parameter and returns a constant.
  function quorum(uint256) public pure override returns (uint256) {
    return QUORUM;
  }

  /// @inheritdoc Governor
  function _execute(
    uint256 proposalId,
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    bytes32 descriptionHash
  ) internal virtual override(Governor, RadworksGovernorTimelockCompound) {
    return RadworksGovernorTimelockCompound._execute(
      proposalId, targets, values, calldatas, descriptionHash
    );
  }

  /// @inheritdoc Governor
  function _cancel(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    bytes32 descriptionHash
  ) internal virtual override(Governor, RadworksGovernorTimelockCompound) returns (uint256) {
    return RadworksGovernorTimelockCompound._cancel(targets, values, calldatas, descriptionHash);
  }

  /// @inheritdoc Governor
  function _executor()
    internal
    view
    virtual
    override(Governor, RadworksGovernorTimelockCompound)
    returns (address)
  {
    return RadworksGovernorTimelockCompound._executor();
  }
}
