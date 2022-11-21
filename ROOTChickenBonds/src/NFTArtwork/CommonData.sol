// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

import "./EggTraitWeights.sol";

enum Size {
    Tiny,
    Small,
    Normal,
    Big
}

struct CommonData {
    uint256 tokenID;

    // ChickenBondManager.BondData
    uint256 beanAmount;
    uint256 claimedBBEAN;
    uint256 startTime;
    uint256 endTime;
    uint8 status;

    // IBondNFT.BondExtraData
    uint80 initialHalfDna;
    uint80 finalHalfDna;
    uint48 rootSupply;
    uint48 beanAmount;

    // Attributes derived from the DNA
    EggTraitWeights.BorderColor borderColor;
    EggTraitWeights.CardColor cardColor;
    EggTraitWeights.ShellColor shellColor;
    Size size;

    // Further data derived from the attributes
    bytes borderStyle;
    bytes cardStyle;
    bool hasCardGradient;
    string[2] cardGradient;
    string tokenIDString;
}
