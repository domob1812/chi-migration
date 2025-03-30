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
