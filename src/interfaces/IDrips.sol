// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.4;

interface IDrips {
  type StreamConfig is uint256;

  struct AccountMetadata {
    bytes32 key;
    bytes value;
  }

  struct SplitsReceiver {
    uint256 accountId;
    uint32 weight;
  }

  struct StreamReceiver {
    uint256 accountId;
    StreamConfig config;
  }

  struct StreamsHistory {
    bytes32 streamsHash;
    StreamReceiver[] receivers;
    uint32 updateTime;
    uint32 maxEnd;
  }

  event AccountMetadataEmitted(uint256 indexed accountId, bytes32 indexed key, bytes value);
  event AdminChanged(address previousAdmin, address newAdmin);
  event BeaconUpgraded(address indexed beacon);
  event Collectable(uint256 indexed accountId, address indexed erc20, uint128 amt);
  event Collected(uint256 indexed accountId, address indexed erc20, uint128 collected);
  event DriverAddressUpdated(
    uint32 indexed driverId, address indexed oldDriverAddr, address indexed newDriverAddr
  );
  event DriverRegistered(uint32 indexed driverId, address indexed driverAddr);
  event Given(
    uint256 indexed accountId, uint256 indexed receiver, address indexed erc20, uint128 amt
  );
  event NewAdminProposed(address indexed currentAdmin, address indexed newAdmin);
  event Paused(address indexed pauser);
  event PauserGranted(address indexed pauser, address indexed admin);
  event PauserRevoked(address indexed pauser, address indexed admin);
  event ReceivedStreams(
    uint256 indexed accountId, address indexed erc20, uint128 amt, uint32 receivableCycles
  );
  event Split(
    uint256 indexed accountId, uint256 indexed receiver, address indexed erc20, uint128 amt
  );
  event SplitsReceiverSeen(bytes32 indexed receiversHash, uint256 indexed accountId, uint32 weight);
  event SplitsSet(uint256 indexed accountId, bytes32 indexed receiversHash);
  event SqueezedStreams(
    uint256 indexed accountId,
    address indexed erc20,
    uint256 indexed senderId,
    uint128 amt,
    bytes32[] streamsHistoryHashes
  );
  event StreamReceiverSeen(
    bytes32 indexed receiversHash, uint256 indexed accountId, StreamConfig config
  );
  event StreamsSet(
    uint256 indexed accountId,
    address indexed erc20,
    bytes32 indexed receiversHash,
    bytes32 streamsHistoryHash,
    uint128 balance,
    uint32 maxEnd
  );
  event Unpaused(address indexed pauser);
  event Upgraded(address indexed implementation);
  event Withdrawn(address indexed erc20, address indexed receiver, uint256 amt);

  function AMT_PER_SEC_EXTRA_DECIMALS() external view returns (uint8);
  function AMT_PER_SEC_MULTIPLIER() external view returns (uint160);
  function DRIVER_ID_OFFSET() external view returns (uint8);
  function MAX_SPLITS_RECEIVERS() external view returns (uint256);
  function MAX_STREAMS_RECEIVERS() external view returns (uint256);
  function MAX_TOTAL_BALANCE() external view returns (uint128);
  function TOTAL_SPLITS_WEIGHT() external view returns (uint32);
  function acceptAdmin() external;
  function admin() external view returns (address);
  function allPausers() external view returns (address[] memory pausersList);
  function balanceAt(
    uint256 accountId,
    address erc20,
    StreamReceiver[] memory currReceivers,
    uint32 timestamp
  ) external view returns (uint128 balance);
  function balances(address erc20)
    external
    view
    returns (uint128 streamsBalance, uint128 splitsBalance);
  function collect(uint256 accountId, address erc20) external returns (uint128 amt);
  function collectable(uint256 accountId, address erc20) external view returns (uint128 amt);
  function cycleSecs() external view returns (uint32);
  function driverAddress(uint32 driverId) external view returns (address driverAddr);
  function emitAccountMetadata(uint256 accountId, AccountMetadata[] memory accountMetadata)
    external;
  function give(uint256 accountId, uint256 receiver, address erc20, uint128 amt) external;
  function grantPauser(address pauser) external;
  function hashSplits(SplitsReceiver[] memory receivers)
    external
    pure
    returns (bytes32 receiversHash);
  function hashStreams(StreamReceiver[] memory receivers)
    external
    pure
    returns (bytes32 streamsHash);
  function hashStreamsHistory(
    bytes32 oldStreamsHistoryHash,
    bytes32 streamsHash,
    uint32 updateTime,
    uint32 maxEnd
  ) external pure returns (bytes32 streamsHistoryHash);
  function implementation() external view returns (address);
  function isPaused() external view returns (bool);
  function isPauser(address pauser) external view returns (bool isAddrPauser);
  function minAmtPerSec() external view returns (uint160);
  function nextDriverId() external view returns (uint32 driverId);
  function pause() external;
  function proposeNewAdmin(address newAdmin) external;
  function proposedAdmin() external view returns (address);
  function proxiableUUID() external view returns (bytes32);
  function receivableStreamsCycles(uint256 accountId, address erc20)
    external
    view
    returns (uint32 cycles);
  function receiveStreams(uint256 accountId, address erc20, uint32 maxCycles)
    external
    returns (uint128 receivedAmt);
  function receiveStreamsResult(uint256 accountId, address erc20, uint32 maxCycles)
    external
    view
    returns (uint128 receivableAmt);
  function registerDriver(address driverAddr) external returns (uint32 driverId);
  function renounceAdmin() external;
  function revokePauser(address pauser) external;
  function setSplits(uint256 accountId, SplitsReceiver[] memory receivers) external;
  function setStreams(
    uint256 accountId,
    address erc20,
    StreamReceiver[] memory currReceivers,
    int128 balanceDelta,
    StreamReceiver[] memory newReceivers,
    uint32 maxEndHint1,
    uint32 maxEndHint2
  ) external returns (int128 realBalanceDelta);
  function split(uint256 accountId, address erc20, SplitsReceiver[] memory currReceivers)
    external
    returns (uint128 collectableAmt, uint128 splitAmt);
  function splitResult(uint256 accountId, SplitsReceiver[] memory currReceivers, uint128 amount)
    external
    view
    returns (uint128 collectableAmt, uint128 splitAmt);
  function splitsHash(uint256 accountId) external view returns (bytes32 currSplitsHash);
  function splittable(uint256 accountId, address erc20) external view returns (uint128 amt);
  function squeezeStreams(
    uint256 accountId,
    address erc20,
    uint256 senderId,
    bytes32 historyHash,
    StreamsHistory[] memory streamsHistory
  ) external returns (uint128 amt);
  function squeezeStreamsResult(
    uint256 accountId,
    address erc20,
    uint256 senderId,
    bytes32 historyHash,
    StreamsHistory[] memory streamsHistory
  ) external view returns (uint128 amt);
  function streamsState(uint256 accountId, address erc20)
    external
    view
    returns (
      bytes32 streamsHash,
      bytes32 streamsHistoryHash,
      uint32 updateTime,
      uint128 balance,
      uint32 maxEnd
    );
  function unpause() external;
  function updateDriverAddress(uint32 driverId, address newDriverAddr) external;
  function upgradeTo(address newImplementation) external;
  function upgradeToAndCall(address newImplementation, bytes memory data) external payable;
  function withdraw(address erc20, address receiver, uint256 amt) external;
}
