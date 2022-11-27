// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

import "./IBEANToken.sol";
import "./IBBEANToken.sol";
import "./ICurvePool.sol";
import "./Interfaces/IBeanstalk.sol";
import "/IBAMM.sol";
import "Beanstalk/protocol/contracts/libraries/Token/LibTransfer.sol";

interface IChickenBondManager {
    // Valid values for `status` returned by `getBondData()`
    enum BondStatus {
        nonExistent,
        active,
        chickenedOut,
        chickenedIn
    }

    function beanToken() external view returns (IBEANToken);
    function bBEANToken() external view returns (IBBEANToken);
    function curvePool() external view returns (ICurvePool);
    function beanstalk() external view returns (IBeanstalk);

    // constants
    function INDEX_OF_ROOT_TOKEN_IN_CURVE_POOL() external pure returns (int128);

    function createBond(uint256 _RootAmount, LibTransfer.From fromMode) external returns (uint256);
    function createBondWithPermit(
        address owner, 
        uint256 amount, 
        uint256 deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external returns (uint256);
    function chickenOut(uint256 _bondID, uint256 _minROOT, LibTransfer.To toMode) external;
    function chickenIn(uint256 _bondID) external;
    function redeem(uint256 _bROOTToRedeem, LibTransfer.To toMode) external returns (uint256, uint256);

    // getters
    function calcRedemptionFeePercentage(uint256 _fractionOfbRootToRedeem) external view returns (uint256);
    function getBondData(uint256 _bondID) external view returns (
        uint112 beanAmount, 
        uint96 rootBDV, 
        uint40 startTime, 
        uint8 status, 
        uint40 endTime, 
        uint216 claimedBRoot
    );
    function getRootToAcquire(uint256 _bondID) external view returns (uint256);
    function calcAccruedBRoot(uint256 _bondID) external view returns (uint256);
    function calcBondBRootCap(uint256 _bondID) external view returns (uint256);
    function pendingROOT() external view returns (uint256);
    function totalAcquiredRoot() external view returns (uint256);
    function permanentRoot() external view returns (uint256);
    function getReserves() external view returns(uint256,uint160,uint96,uint256);
    function calcSystemBackingRatio() external view returns (uint256);
    function calcUpdatedAccrualParameter() external view returns (uint256);
}
