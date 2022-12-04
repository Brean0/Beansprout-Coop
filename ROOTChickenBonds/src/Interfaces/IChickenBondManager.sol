// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.4.23 <=0.9.0;

import "./IRoot.sol";
import "./IBRoot.sol";
import "./IBeanstalk.sol";
//import "Beanstalk/protocol/contracts/libraries/Token/LibTransfer.sol";

interface IChickenBondManager {
    // Valid values for `status` returned by `getBondData()`

    // enum From {
    //     EXTERNAL,
    //     INTERNAL,
    //     EXTERNAL_INTERNAL,
    //     INTERNAL_TOLERANT
    // }
    // enum To {
    //     EXTERNAL,
    //     INTERNAL
    // }

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


    function rootToken() external view returns (IRoot);
    function bRoot() external view returns (IBRoot);
    function beanstalk() external view returns (IBeanstalk);

    // constants
    //function INDEX_OF_ROOT_TOKEN_IN_CURVE_POOL() external pure returns (int128);

    function createBond(uint256 _RootAmount) external returns (uint256);
    function createBondWithPermit(
        address owner, 
        uint256 amount,
        uint256 deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external returns (uint256);
    function chickenOut(uint256 _bondID, uint256 _minROOT, To toMode) external;
    function chickenIn(uint256 _bondID) external;
    function redeem(uint256 _bROOTToRedeem, To toMode) external returns (uint256);

    // getters
    function calcRedemptionFeePercentage(uint256 _fractionOfbRootToRedeem) external view returns (uint256);
    function getBondData(uint256 _bondID) external view returns (BondData memory bond);
    function getRootToAcquire(uint256 _bondID) external view returns (uint256);
    function calcAccruedBRoot(uint256 _bondID) external view returns (uint256);
    function calcBondBRootCap(uint256 _bondID) external view returns (uint256);
    function pendingRoot() external view returns (uint256);
    function totalAcquiredRoot() external view returns (uint256);
    function permanentRoot() external view returns (uint256);
    function getReserves() external view returns(uint256,uint160,uint96,uint256);
    function calcSystemBackingRatio() external view returns (uint256);
    function calcUpdatedAccrualParameter() external view returns (uint256);
}
