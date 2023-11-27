# Radworks Governor Bravo Upgrade

An upgrade to a "Bravo" compatible Governor for the Radworks DAO, built using the OpenZeppelin Bravo governor.

#### Getting started

Clone the repo

```bash
git clone git@github.com:ScopeLift/radworks-governor-upgrade.git
cd radworks-governor-upgrade
```

Copy the `.env.template` file and populate it with values

```bash
cp .env.template .env
# Open the .env file and add your values
```

```bash
forge install
forge build
forge test
```

### Formatting

Formatting is done via [scopelint](https://github.com/ScopeLift/scopelint). To install scopelint, run:

```bash
cargo install scopelint
```

#### Apply formatting

```bash
scopelint fmt
```

#### Check formatting

```bash
scopelint check
```

#### Scopelint spec compatibility

Some tests will not show up when running `scopelint spec` because the methods they are testing are inherited in the `RadworksGovernor`. In order to get an accurate picture of the tests with `scopelint spec` add an explicit `propose` method to the `RadworksGovernor`. It should look like this:

```
 function propose(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    string memory description
  ) public override(Governor, IGovernor) returns (uint256) {
    return Governor.propose(targets, values, calldatas, description);
  }
```

## Scripts

- `script/Deploy.s.sol` - Deploys the RadworksGovernor contract

To test these scripts locally, start a local fork with anvil:

```bash
anvil --fork-url YOUR_RPC_URL --fork-block-number 18514244
```

Then execute the deploy script.

_NOTE_: You must populate the `DEPLOYER_PRIVATE_KEY` in your `.env` file for this to work.

```bash
forge script script/Deploy.s.sol --tc Deploy --rpc-url http://localhost:8545 --broadcast
```

Pull the contract address for the new Governor from the deploy script address, then execute the Proposal script.

_NOTE_: You must populate the `PROPOSER_PRIVATE_KEY` in your `.env` file for this to work. Additionally, the
private key must correspond to the `proposer` address defined in the `Proposal.s.sol` script. You can update this
variable to an address you control, however the proposal itself will still revert in this case, unless you provide
the private key of an address that has sufficient RAD Token delegation to have the right to submit a proposal.

```bash
forge script script/Propose.s.sol --sig "run(address)" NEW_GOVERNOR_ADDRESS --rpc-url http://localhost:8545 --broadcast
```

### Testing issues

This repo heavily leverages fuzz fork tests causing a significant number of RPC requests to be made. We leverage caching to minimize the number of RPC calls after the tests are run for the first time, but running these tests for the first time may cause timeouts and consume a significant number of RPC calls.
