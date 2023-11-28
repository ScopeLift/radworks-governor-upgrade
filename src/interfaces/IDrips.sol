// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

interface IDrips {
  function admin() external view returns (address);
  function proposeNewAdmin(address newAdmin) external;
  function acceptAdmin() external;
  function renounceAdmin() external;
  function grantPauser(address pauser) external;
  function revokePauser(address pauser) external;
  function isPauser(address pauser) external view returns (bool);
  function allPausers() external view returns (address[] memory);
  function isPaused() external view returns (bool);
  function pause() external;
  function unpause() external;
}
