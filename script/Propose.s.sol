// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {ICompoundTimelock} from
  "@openzeppelin/contracts/governance/extensions/GovernorTimelockCompound.sol";

import {RadworksGovernor} from "src/RadworksGovernor.sol";
import {IGovernorAlpha} from "src/interfaces/IGovernorAlpha.sol";

contract Propose is Script {
  IGovernorAlpha constant GOVERNOR_ALPHA =
    IGovernorAlpha(0x690e775361AD66D1c4A25d89da9fCd639F5198eD);

  // TODO: resolve the list of large delegates with tally
  address PROPOSER = 0x464D78a5C97A2E2E9839C353ee9B6d4204c90B0b; // cloudhead.eth

  function propose(RadworksGovernor _newGovernor) internal returns (uint256 _proposalId) {
    address[] memory _targets = new address[](2);
    uint256[] memory _values = new uint256[](2);
    string[] memory _signatures = new string [](2);
    bytes[] memory _calldatas = new bytes[](2);

    _targets[0] = GOVERNOR_ALPHA.timelock();
    _values[0] = 0;
    _signatures[0] = "setPendingAdmin(address)";
    _calldatas[0] = abi.encode(address(_newGovernor));

    _targets[1] = address(_newGovernor);
    _values[1] = 0;
    _signatures[1] = "__acceptAdmin()";
    _calldatas[1] = "";

    return GOVERNOR_ALPHA.propose(
      _targets, _values, _signatures, _calldatas, "Upgrade to Governor Bravo"
    );
  }

  /// @dev After the new Governor is deployed on mainnet, this can move from a parameter to a const
  function run(RadworksGovernor _newGovernor) public returns (uint256 _proposalId) {
    // The expectation is the key loaded here corresponds to the address of the `proposer` above.
    // When running as a script, broadcast will fail if the key is not correct.
    uint256 _proposerKey = vm.envOr(
      "PROPOSER_PRIVATE_KEY",
      uint256(0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d)
    );
    vm.rememberKey(_proposerKey);

    vm.startBroadcast(PROPOSER);
    _proposalId = propose(_newGovernor);
    vm.stopBroadcast();
    return _proposalId;
  }
}
