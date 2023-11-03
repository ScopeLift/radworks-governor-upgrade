// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";

import {Deploy} from "script/Deploy.s.sol";
import {DeployInput} from "script/DeployInput.sol";
import {
  ERC20VotesComp,
  GovernorVotesComp
} from "@openzeppelin/contracts/governance/extensions/GovernorVotesComp.sol";
import {RadworksGovernor} from "src/RadworksGovernor.sol";
import {Constants} from "test/Constants.sol";

abstract contract RadworksGovernorTest is Test, DeployInput, Constants {
  // using FixedPointMathLib for uint256;

  ERC20VotesComp poolToken = ERC20VotesComp(RAD_TOKEN);

  struct Delegate {
    string handle;
    address addr;
    uint96 votes;
  }

  Delegate[] delegates;

  RadworksGovernor governorBravo;

  function setUp() public virtual {
    // The latest block when this test was written. If you update the fork block
    // make sure to also update the top 6 delegates below.
    uint256 _forkBlock = 18_514_244;

    vm.createSelectFork(vm.rpcUrl("mainnet"), _forkBlock);

    // Taken from https://www.tally.xyz/gov/radworks/delegates?sort=voting_power_desc.
    // If you update these delegates (including updating order in the array),
    // make sure to update any tests that reference specific delegates. The last delegate is the
    // proposer and lower in the voting power than the above link.
    // TODO: resolve the list of large delegates with tally
    Delegate[] memory _delegates = new Delegate[](3);
    _delegates[0] = Delegate("Delegate 0", 0x288703AA4e65dD244680FaefA742C488b7CD1992, 4.24e6);
    _delegates[1] = Delegate("Delegate 1", 0x69dceee155C31eA0c8354F90BDD65C12FaF5A00a, 1.86e6);
    // _delegates[2] = Delegate("Delegate 2", 0x464D78a5C97A2E2E9839C353ee9B6d4204c90B0b, 1.58e6);
    // _delegates[3] = Delegate("Delegate 3", 0xc74f55155C41dfB90C122A1702b49C8295D9a724, 988.24e3);
    // _delegates[4] = Delegate("Delegate 4", 0xBD8d617Ac53c5Efc5fBDBb51d445f7A2350D4940, 680.27e6);
    _delegates[2] = Delegate("proposer", PROPOSER, 1.58e6);

    // Fetch up-to-date voting weight for the top delegates.
    for (uint256 i; i < _delegates.length; i++) {
      Delegate memory _delegate = _delegates[i];
      _delegate.votes = poolToken.getCurrentVotes(_delegate.addr);
      delegates.push(_delegate);
    }

    if (_useDeployedGovernorBravo()) {
      // The Radworks contract bravo governor hasn't deployed to mainnet yet, so we're let's not
      // test this yet
      // using Deploy in this repo.
      governorBravo = RadworksGovernor(payable(DEPLOYED_BRAVO_GOVERNOR));
    } else {
      // We still want to exercise the script in these tests to give us
      // confidence that we could deploy again if necessary.
      Deploy _deployScript = new Deploy();
      _deployScript.setUp();
      governorBravo = _deployScript.run();
    }
  }

  function _useDeployedGovernorBravo() internal virtual returns (bool);
}
