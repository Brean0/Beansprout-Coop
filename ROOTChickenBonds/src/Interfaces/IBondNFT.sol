// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.4.23 <0.9.0;

import "openzeppelin-contracts/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "./IChickenBondManager.sol";

interface IBondNFT is IERC721Enumerable {

    enum BondStatus {
        nonExistent,
        active,
        chickenedOut,
        chickenedIn
    }

    /// @dev sadly we must use 2 slots
    // first 4 vars are written at createBond
    // last 3 vars are written at chickenIn/Out
    // we place bondstatus in the first slot as writing a nonzero to a zero slot costs more 
    struct BondData {
        uint112 amount; // Root in bond; very unlikely that a bond will contain > uint112.max ()
        uint96 rootBDV; // Root BDV during time of creation
        uint40 startTime; // Start time of bond; uint40 is more than big enough to store
        BondStatus status; // status of Bond
        uint40 endTime; // End time of bond; same as above
        uint216 claimedBRoot; // Amt of bBEAN claimed (without decimals)
    }

    
   
    function mint(address _bonder) external returns (uint256);
    function chickenBondManager() external view returns (IChickenBondManager);
    function getBondAmount(uint256 _tokenID) external view returns (uint256 amount);
    function getBondStartTime(uint256 _tokenID) external view returns (uint256 startTime);
    function getBondEndTime(uint256 _tokenID) external view returns (uint256 endTime);
    function getBondStatus(uint256 _tokenID) external view returns (IChickenBondManager.BondStatus status);
}
