// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {ICompoundTimelock} from
  "@openzeppelin/contracts/governance/extensions/GovernorTimelockCompound.sol";

import {RadworksGovernor} from "src/RadworksGovernor.sol";
import {IGovernorAlpha} from "src/interfaces/IGovernorAlpha.sol";
import {Constants} from "test/Constants.sol";
import {DeployInput} from "script/DeployInput.sol";

/// @notice Script to submit the proposal to upgrade Radworks governor.
contract Propose is Script, Constants, DeployInput {
  IGovernorAlpha constant RADWORK_GOVERNOR_ALPHA = IGovernorAlpha(GOVERNOR_ALPHA);
  address PROPOSER_ADDRESS = PROPOSER; // abbey

  function propose(RadworksGovernor _newGovernor) internal returns (uint256 _proposalId) {
    address[] memory _targets = new address[](3);
    uint256[] memory _values = new uint256[](3);
    string[] memory _signatures = new string[](3);
    bytes[] memory _calldatas = new bytes[](3);

    _targets[0] = RAD_TOKEN;
    _values[0] = 0;
    _signatures[0] = "transfer(address,uint256)";
    _calldatas[0] = abi.encode(SCOPELIFT_ADDRESS, SCOPELIFT_PAYMENT);

    _targets[1] = RADWORK_GOVERNOR_ALPHA.timelock();
    _values[1] = 0;
    _signatures[1] = "setPendingAdmin(address)";
    _calldatas[1] = abi.encode(address(_newGovernor));

    _targets[2] = address(_newGovernor);
    _values[2] = 0;
    _signatures[2] = "__acceptAdmin()";
    _calldatas[2] = "";

    return RADWORK_GOVERNOR_ALPHA.propose(
      _targets, _values, _signatures, _calldatas, "Upgrade to Governor Bravo"
    );
  }

  /// @dev After the new Governor is deployed on mainnet, `_newGovernor` can become a const
  function run(RadworksGovernor _newGovernor) public returns (uint256 _proposalId) {
    // The expectation is the key loaded here corresponds to the address of the `proposer` above.
    // When running as a script, broadcast will fail if the key is not correct.
    uint256 _proposerKey = vm.envOr(
      "PROPOSER_PRIVATE_KEY",
      uint256(0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d)
    );
    vm.rememberKey(_proposerKey);

    vm.startBroadcast(PROPOSER_ADDRESS);
    _proposalId = propose(_newGovernor);
    vm.stopBroadcast();
    return _proposalId;
  }
}
