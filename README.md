# CHI to WCHI Migration

This is a smart contract and set of supporting scripts that will allow
automatic and mostly trustless claiming of [WCHI](https://github.com/xaya/wchi)
based on a snapshot of CHI balances taken on Xaya Core.

## Test Snapshot

For testing purposes in a real setting, a snapshot has been taken
at Xaya Core block #6'720'224 (block hash
`3046a447c563ed27dccfd67d7fa573494cb3c77975335f6c7aafb103fd7b5601`).
The corresponding UTXO dump is in `data/test-snapshot.csv`.

A dummy token has been deployed, which can be claimed based on this snapshot
but is worthless and only for testing purposes.  The contract address
of the test token is
[`0xE166d0E959E6CEBFBB84Dc54359e2DdA7D01Ba83`](https://polygonscan.com/address/0xE166d0E959E6CEBFBB84Dc54359e2DdA7D01Ba83).

The test contract for the migration claim itself for the test token and snapshot
has been deployed at
[`0x9fF44e6A517045371A8B0eFD908666AFc1618Dfa`](https://polygonscan.com/address/0x9fF44e6A517045371A8B0eFD908666AFc1618Dfa).

## Real Snapshot

The real snapshot for the migration is taking place at **block 7'300'000**
on Xaya Core.  This is block
**`3ee636ba55e3ad77755090f7386ba0a8452d032a021c76941a839a84367a066a`**.

As of the snapshot, the WCHI in circulation are as
follows, based on the total token supply in existence and the
coins held in the
[bridge multisig address](https://etherscan.io/address/0xb33b61af1ea25b738ef6677388fb75f436bc760f)
"in reserve":

    Total token supply:      78'000'000.00000000
    Held in bridge multisig: 58'646'656.50906881
    Circulating supply:      19'353'343.49093119

That amount of WCHI already circulating before the snapshot is matched
by the exact same amount of CHI held in the bridge multisig on the
Xaya network, in output
**`7547964b962dcdad3ea5227642e23b03abbbd22d5859af0db262498625903ced:1`**.
This output is excluded from the snapshot claim on Ethereum, so that
the correct amount of WCHI will be circulating on Ethereum after the
snapshot claim.
