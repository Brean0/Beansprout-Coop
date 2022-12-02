# Beanstalk Coop - Technical Readme
Breans Side project - implmentation of the LUSD Chicken Bonds onto the Beanstalk protocol

As coop is a fork on chicken bonds, refer to Liquitys documentation on how it works: https://github.com/liquity/ChickenBond

## Changes
- The Coop will ultilize the ROOT token, which is an ERC-20 wrapper of Beanstalk's silo deposit. This massively simplifies the development work needed to interact with the silo. This means that a user Chickening Out may get less ROOT than initally bonded, but will have the same BDV as bonding. 
- **The Coop is not immutable. The coop will ultilize a upgradable proxy, controlled via multisig. The multisig will act on the behalf of the will of the token holders**. 
- The convert functionality is removed, as the protocol uses the ROOT token. 
- Because yield is given innately with the ROOT token, the contract does not need external calls to yield aggerators, reducing gas costs signficantly. 
- all pools accrue stalk over time, adding another dimension of yield beyond bean yield. 
- The permenant pool can be ultilized beyond yield for the bROOT holders, subject to governance.
- The bond art is dynamically generated on-chain, similar to liquity. The SVG creation code is within the bond manager contract, rather than its own contract. 
  - art is heavily inspired from Anchor certificate: https://tlatcnfts.untitledfrontier.studio/ 
