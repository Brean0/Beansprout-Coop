// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "./Interfaces/IBondNFT.sol";
import "./console.sol";
import "./Interfaces/ILUSDToken.sol";
import "./Interfaces/IYearnVault.sol";

contract ChickenBondManager is Ownable {

    // ChickenBonds contracts
    IBondNFT public bondNFT;

    // ISLUSDToken public sLUSDToken;
    ILUSDToken public lusdToken;
    
    // External contracts
    IYearnVault yearnLUSDVault;
    // IYearnVault yearnCurveVault;

    // --- Data structures ---

     struct BondData {
        uint256 lusdAmount;
        uint256 startTime;
    }

    uint256 public totalPendingLUSD;
    mapping (uint => BondData) public idToBondData;

    uint256 constant MAX_UINT256 = type(uint256).max;

    // --- Initializer ---

    // TODO: make constructor
    function initialize(address _bondNFTAddress, address _lusdTokenAddress, address _yearnLUSDVault) external onlyOwner {
        bondNFT = IBondNFT(_bondNFTAddress);
        lusdToken = ILUSDToken(_lusdTokenAddress);
        yearnLUSDVault = IYearnVault(_yearnLUSDVault);

        // TODO: Decide between one-time infinite LUSD approval to Yearn vaults (lower gas cost per user tx, less secure) 
        // or limited approval at each bonder action (higher gas cost per user tx, more secure)
        lusdToken.approve(address(yearnLUSDVault), MAX_UINT256);

        renounceOwnership();
    }

    function createBond(uint256 _lusdAmount) external {
        // Mint the bond NFT to the caller and get the bond ID
        uint256 bondID = bondNFT.mint(msg.sender);

        //Record the user’s bond data: bond_amount and start_time
        BondData memory bondData;
        bondData.lusdAmount = _lusdAmount;
        bondData.startTime = block.timestamp;

        idToBondData[bondID] = bondData;

        totalPendingLUSD += _lusdAmount;

        lusdToken.transferFrom(msg.sender, address(this), _lusdAmount);

        // Deposit the LUSD to the Yearn LUSD vault
        yearnLUSDVault.deposit(_lusdAmount);
    } 

    // Chicken out
    function chickenOut(uint _bondID) external {
        _requireCallerOwnsBond(_bondID);

        uint bondedLUSD = idToBondData[_bondID].lusdAmount;
        
        totalPendingLUSD -= bondedLUSD;
        delete idToBondData[_bondID];

        yearnLUSDVault.withdraw(bondedLUSD);

        // Send bonded LUSD back to caller and burn their bond NFT
        lusdToken.transfer(msg.sender, bondedLUSD);
        bondNFT.burn(_bondID);
    }

    function _requireCallerOwnsBond(uint256 _bondID) internal {
        require(msg.sender == bondNFT.ownerOf(_bondID), "CBM: Caller must own the bond");
    }
}
