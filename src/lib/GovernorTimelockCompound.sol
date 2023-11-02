// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.6.0) (governance/extensions/GovernorTimelockCompound.sol)
//
// The Radworks Timelock is not compatible with the Governor Alpha Timelock interface. This
// meant we had to fork the contracts that interact with the timelock and replace the Timelock
// interface with the Radworks Timelock interface. Also, if Radworks decides to change the
// Timelock in the future then it must conform to the Radworks Timelock interface.
//
// Radworks Timelock interface:
// https://etherscan.io/address/0xB3a87172F555ae2a2AB79Be60B336D2F7D0187f0#code#F1#L306
// Governor Alpha Timelock interface:
// https://github.com/compound-finance/compound-protocol/blob/a3214f67b73310d547e00fc578e8355911c9d376/contracts/Governance/GovernorAlpha.sol#L320
// forgefmt: disable-start

pragma solidity ^0.8.0;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IGovernorTimelock} from
  "@openzeppelin/contracts/governance/extensions/IGovernorTimelock.sol";
import {IRadworksTimelock} from "src/interfaces/IRadworksTimelock.sol";
import {Timers} from "@openzeppelin/contracts/utils/Timers.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

/**
 * @dev Extension of {Governor} that binds the execution process to a Compound Timelock. This adds a delay, enforced by
 * the external timelock to all successful proposal (in addition to the voting duration). The {Governor} needs to be
 * the admin of the timelock for any operation to be performed. A public, unrestricted,
 * {GovernorTimelockCompound-__acceptAdmin} is available to accept ownership of the timelock.
 *
 * Using this model means the proposal will be operated by the {TimelockController} and not by the {Governor}. Thus,
 * the assets and permissions must be attached to the {TimelockController}. Any asset sent to the {Governor} will be
 * inaccessible.
 *
 * _Available since v4.3._
 */
abstract contract GovernorTimelockCompound is IGovernorTimelock, Governor {
  using SafeCast for uint256;
  using Timers for Timers.Timestamp;

  struct ProposalTimelock {
    Timers.Timestamp timer;
  }

  /// @dev The interface for this variable was changed to conform to the Radworks Timelock interface.
  ///
  /// Original openzeppelin:
  /// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/49c0e4370d0cc50ea6090709e3835a3091e33ee2/contracts/governance/extensions/GovernorTimelockCompound.sol#L31
  IRadworksTimelock private _timelock;

  mapping(uint256 => ProposalTimelock) private _proposalTimelocks;

  /**
   * @dev Emitted when the timelock controller used for proposal execution is modified.
   */
  event TimelockChange(address oldTimelock, address newTimelock);

  /**
   * @dev Set the timelock.
   * @dev The timelock interface was changed from the original Openzeppelin source to conform to the Radworks interface.
   *
   * Original Openzeppelin source:
   * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/49c0e4370d0cc50ea6090709e3835a3091e33ee2/contracts/governance/extensions/GovernorTimelockCompound.sol#L43
   */
  constructor(IRadworksTimelock timelockAddress) {
    _updateTimelock(timelockAddress);
  }

  /**
   * @dev See {IERC165-supportsInterface}.
   */
  function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(Governor, IERC165)
    returns (bool)
  {
    return
      interfaceId == type(IGovernorTimelock).interfaceId || super.supportsInterface(interfaceId);
  }

  /**
   * @dev Overridden version of the {Governor-state} function with added support for the `Queued` and `Expired` status.
   * @dev The _timelock.gracePeriod() was changed from _timelock.GRACE_PERIOD() in the original Openzeppelin contract.
   *
   * Original Openzeppelin source:
   * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/49c0e4370d0cc50ea6090709e3835a3091e33ee2/contracts/governance/extensions/GovernorTimelockCompound.sol#L67
   */
  function state(uint256 proposalId)
    public
    view
    virtual
    override(IGovernor, Governor)
    returns (ProposalState)
  {
    ProposalState status = super.state(proposalId);

    if (status != ProposalState.Succeeded) return status;

    uint256 eta = proposalEta(proposalId);
    if (eta == 0) return status;
    else if (block.timestamp >= eta + _timelock.gracePeriod()) return ProposalState.Expired;
    else return ProposalState.Queued;
  }

  /**
   * @dev Public accessor to check the address of the timelock
   */
  function timelock() public view virtual override returns (address) {
    return address(_timelock);
  }

  /**
   * @dev Public accessor to check the eta of a queued proposal
   */
  function proposalEta(uint256 proposalId) public view virtual override returns (uint256) {
    return _proposalTimelocks[proposalId].timer.getDeadline();
  }

  /**
   * @dev Function to queue a proposal to the timelock.
   */
  function queue(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    bytes32 descriptionHash
  ) public virtual override returns (uint256) {
    uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);

    require(state(proposalId) == ProposalState.Succeeded, "Governor: proposal not successful");

    uint256 eta = block.timestamp + _timelock.delay();
    _proposalTimelocks[proposalId].timer.setDeadline(eta.toUint64());
    for (uint256 i = 0; i < targets.length; ++i) {
      require(
        !_timelock.queuedTransactions(
          keccak256(abi.encode(targets[i], values[i], "", calldatas[i], eta))
        ),
        "GovernorTimelockCompound: identical proposal action already queued"
      );
      _timelock.queueTransaction(targets[i], values[i], "", calldatas[i], eta);
    }

    emit ProposalQueued(proposalId, eta);

    return proposalId;
  }

  /**
   * @dev Overridden execute function that run the already queued proposal through the timelock.
   */
  function _execute(
    uint256 proposalId,
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    bytes32 /*descriptionHash*/
  ) internal virtual override {
    uint256 eta = proposalEta(proposalId);
    require(eta > 0, "GovernorTimelockCompound: proposal not yet queued");
    // In the original contract, the _timelock is not casted to an address. Failing to cast it causes a compile error "Explicit type conversion not allowed from "contract IRadworksTimelock" to "address payable".".
    // We explicitly cast to an address to solve this error.
    //
    // Original Openzeppelin line:
    // https://github.com/OpenZeppelin/openzeppelin-contracts/blob/49c0e4370d0cc50ea6090709e3835a3091e33ee2/contracts/governance/extensions/GovernorTimelockCompound.sol#L128
    Address.sendValue(payable(address(_timelock)), msg.value);
    for (uint256 i = 0; i < targets.length; ++i) {
      _timelock.executeTransaction(targets[i], values[i], "", calldatas[i], eta);
    }
  }

  /**
   * @dev Overridden version of the {Governor-_cancel} function to cancel the timelocked proposal if it as already 
   * been queued.
   */
  function _cancel(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    bytes32 descriptionHash
  ) internal virtual override returns (uint256) {
    uint256 proposalId = super._cancel(targets, values, calldatas, descriptionHash);

    uint256 eta = proposalEta(proposalId);
    if (eta > 0) {
      for (uint256 i = 0; i < targets.length; ++i) {
        _timelock.cancelTransaction(targets[i], values[i], "", calldatas[i], eta);
      }
      _proposalTimelocks[proposalId].timer.reset();
    }

    return proposalId;
  }

  /**
   * @dev Address through which the governor executes action. In this case, the timelock.
   */
  function _executor() internal view virtual override returns (address) {
    return address(_timelock);
  }

  /**
   * @dev Accept admin right over the timelock.
   */
  // solhint-disable-next-line private-vars-leading-underscore
  function __acceptAdmin() public {
    _timelock.acceptAdmin();
  }

  /**
   * @dev Public endpoint to update the underlying timelock instance. Restricted to the timelock itself, so updates
   * must be proposed, scheduled, and executed through governance proposals.
   *
   * For security reasons, the timelock must be handed over to another admin before setting up a new one. The two
   * operations (hand over the timelock) and do the update can be batched in a single proposal.
   *
   * Note that if the timelock admin has been handed over in a previous operation, we refuse updates made through the
   * timelock if admin of the timelock has already been accepted and the operation is executed outside the scope of
   * governance.

   * CAUTION: It is not recommended to change the timelock while there are other queued governance proposals.
   * @dev The interface for `newTimelock` was changed to conform to the Radworks Timelock interface.
   *
   * Original Openzeppelin source:
   * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/49c0e4370d0cc50ea6090709e3835a3091e33ee2/contracts/governance/extensions/GovernorTimelockCompound.sol#L185
   */
  function updateTimelock(IRadworksTimelock newTimelock) external virtual onlyGovernance {
    _updateTimelock(newTimelock);
  }


  /**
   * @dev The interface for `newTimelock` was changed to conform to the Radworks Timelock interface.
   *
   * Original Openzeppelin source:
   * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/49c0e4370d0cc50ea6090709e3835a3091e33ee2/contracts/governance/extensions/GovernorTimelockCompound.sol#L189
   */
  function _updateTimelock(IRadworksTimelock newTimelock) private {
    emit TimelockChange(address(_timelock), address(newTimelock));
    _timelock = newTimelock;
  }
}
