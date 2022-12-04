// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.4.23 <0.9.0;

import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./utils/ChickenMath.sol";

import "./Interfaces/IBondNFT.sol";
import "./Interfaces/IRoot.sol";
import "./Interfaces/IBRoot.sol";
import "./Interfaces/IBeanstalk.sol";
import "./Interfaces/IChickenBondManager.sol";
import "./Interfaces/ICurveLiquidityGaugeV5.sol";
// import "forge-std/console.sol";

// current todos: 
contract ChickenBondManager is ChickenMath, IChickenBondManager {


     // External contracts and addresses
    address private constant BEANSTALK = 0xC1E088fC1323b20BCBee9bd1B9fC9546db5624C5;
    address private constant BSM = 0x21DE18B6A8f78eDe6D16C50A167f6B222DC08DF7;
    address private constant ROOTTOKEN = 0x77700005BEA4DE0A78b956517f099260C2CA9a26;
    address private constant BROOT = 0xC1E088fC1323b20BCBee9bd1B9fC9546db5624C5;
    address private constant BONDNFT = 0xC1E088fC1323b20BCBee9bd1B9fC9546db5624C5;
    address private constant CURVE_GAUGE = 0xC1E088fC1323b20BCBee9bd1B9fC9546db5624C5;

    // ChickenBonds contracts and addresses
    IBondNFT public constant bondNFT = IBondNFT(BONDNFT);
    IBRoot public constant bRoot = IBRoot(BROOT);
    IRoot public constant rootToken = IRoot(ROOTTOKEN);
    IBeanstalk public constant beanstalk = IBeanstalk(BEANSTALK);
    ICurveLiquidityGaugeV5 public constant curveLiquidityGauge = ICurveLiquidityGaugeV5(CURVE_GAUGE);
   

    // TODO: determine if needed for Beanstalk (3% in liquity)
    // the chicken in fee incentivizes bRoot-BEAN3CRV LP 
    // the fee could be removed in a couple of ways: 
    // 2: We ask bean sprout for a grant for the fee
    uint256 public CHICKEN_IN_AMM_FEE;
    BucketData public rootBucket;

    
    /*//////////////////////////////////////////////////////////////
                            DATA STRUCTURES
    //////////////////////////////////////////////////////////////*/
    
    struct Params {
        uint256 targetAverageAgeSeconds;        // Average outstanding bond age above which the controller will adjust `accrualParameter` in order to speed up accrual
        uint256 initialAccrualParameter;        // Initial value for `accrualParameter`
        uint256 minimumAccrualParameter;        // Stop adjusting `accrualParameter` when this value is reached
        uint256 accrualAdjustmentRate;          // `accrualParameter` is multiplied `1 - accrualAdjustmentRate` every time there's an adjustment
        uint256 accrualAdjustmentPeriodSeconds; // The duration of an adjustment period in seconds
        uint256 chickenInAMMFee;                // Fraction of bonded amount that is sent to Curve Liquidity Gauge to incentivize ROOT-bRoot liquidity
        uint256 bootstrapPeriodChickenIn;       // Min duration of first chicken-in
        uint256 bootstrapPeriodRedeem;          // Redemption lock period after first chicken in
        uint256 minbRootSupply;                 // Minimum amount of bRoot supply that must remain after a redemption
        uint256 minBondAmount;                  // Minimum amount of ROOT that needs to be bonded
        uint256 redemptionFeeBeta;              // Parameter by which to divide the redeemed fraction, in order to calculate the new base rate from a redemption
        uint256 redemptionFeeMinuteDecayFactor; // Factor by which redemption fee decays (exponentially) every minute
    }

    /// @dev lastBDV and reserve are packed into 1 slot as they are updated in the same call
    /// the reserve would have to hold 1.4 nonillion Root to overflow
    /// RootBDV would have to be 1 trillion per Root to overflow
    // maybe im not bullish enough
    struct BucketData { 
        uint256 pending; // the amount of Roots in the pending Bucket 
        uint160 reserve; // the amount of Roots in the reserve Bucket
        uint96 lastBDV; // the RootBDV from the last earn call. Used to transfer Root from perm -> reserve for yield
    }

    uint256 public firstChickenInTime; // Timestamp of the first chicken in after bRoot supply is zero
    uint256 public totalWeightedStartTimes; // Sum of `beanAmount * startTime` for all outstanding bonds (used to tell weighted average bond age)
    uint256 public lastRedemptionTime; // The timestamp of the latest redemption
    uint256 public baseRedemptionRate; // The latest base redemption rate
    mapping (uint256 => BondData) private idToBondData;

    /* migration: flag which determines whether the system is in migration mode.

    When migration mode has been triggered:
    - Bond creation is disabled
    - Users with an existing bond may still chicken in or out
    - Chicken-ins will no longer send the ROOT surplus to the permanent bucket. Instead, they refund the surplus to the bonder
    - bRoot holders may still redeem
    - Redemption fees are zero
    */
    bool public migration;

    uint256 public countChickenIn;
    uint256 public countChickenOut;
    
    // --- Constants ---
    uint256 constant MAX_UINT256 = type(uint256).max;
    uint256 constant SECONDS_IN_ONE_MINUTE = 60;

    uint256 public immutable BOOTSTRAP_PERIOD_CHICKEN_IN; // Min duration of first chicken-in
    uint256 public immutable BOOTSTRAP_PERIOD_REDEEM;     // Redemption lock period after first chicken in
    //uint256 public immutable BOOTSTRAP_PERIOD_SHIFT;      // Period after launch during which shifter functions are disabled
    uint256 public immutable MIN_BROOT_SUPPLY;            // Minimum amount of bRoot supply that must remain after a redemption
    uint256 public immutable MIN_BOND_AMOUNT;             // Minimum amount of LUSD that needs to be bonded
    // This is the minimum amount the permanent bucket needs to be increased by an attacker (through previous chicken in or redemption fee),
    // in order to manipulate the obtained NFT. If the attacker finds the desired outcome at attempt N,
    // the permanent increase should be N * NFT_RANDOMNESS_DIVISOR.
    // It also means that as long as Permanent doesn’t change in that order of magnitude, attacker can try to manipulate
    // only changing the event.
    //uint256 public immutable NFT_RANDOMNESS_DIVISOR;

    /*
     * BETA: 18 digit decimal. Parameter by which to divide the redeemed fraction, in order to calc the new base rate from a redemption.
     * Corresponds to (1 / ALPHA) in the Liquity white paper.
     */
    uint256 public immutable BETA;
    uint256 public immutable MINUTE_DECAY_FACTOR;
    // --- Accrual control variables ---

    // `block.timestamp` of the block in which this contract was deployed.
    uint256 public immutable deploymentTimestamp;

    // Average outstanding bond age above which the controller will adjust `accrualParameter` in order to speed up accrual.
    uint256 public immutable targetAverageAgeSeconds;

    // Stop adjusting `accrualParameter` when this value is reached.
    uint256 public immutable minimumAccrualParameter;

    // Number between 0 and 1. `accrualParameter` is multiplied by this every time there's an adjustment.
    uint256 public immutable accrualAdjustmentMultiplier;

    // The duration of an adjustment period in seconds. The controller performs at most one adjustment per every period.
    uint256 public immutable accrualAdjustmentPeriodSeconds;

    // The number of seconds it takes to accrue 50% of the cap, represented as an 18 digit fixed-point number.
    uint256 public accrualParameter;

    // Counts the number of adjustment periods since deployment.
    // Updated by operations that change the average outstanding bond age (createBond, chickenIn, chickenOut).
    // Used by `_calcUpdatedAccrualParameter` to tell whether it's time to perform adjustments, and if so, how many times
    // (in case the time elapsed since the last adjustment is more than one adjustment period).
    uint256 public accrualAdjustmentPeriodCount;

    // --- Events ---

    event BaseRedemptionRateUpdated(uint256 _baseRedemptionRate);
    event LastRedemptionTimeUpdated(uint256 _lastRedemptionFeeOpTime);
    event BondCreated(address indexed bonder, uint256 bondId, uint256 amount);
    event BondClaimed(
        address indexed bonder,
        uint256 bondId,
        uint256 amount,
        uint256 bRootAmount,
        uint256 rootSurplus,
        uint256 chickenInFeeAmount,
        bool migration
    );
    event BondCancelled(
        address indexed bonder, 
        uint256 bondId, 
        uint256 withdrawnRootAmount
    );
    event BRootRedeemed(
        address indexed redeemer, 
        uint256 bRootAmount,
        uint256 reserveRootToRedeem
    );
    event MigrationTriggered(uint256 previousPermanentROOT);
    event AccrualParameterUpdated(uint256 accrualParameter);

    // --- Constructor ---

    constructor (Params memory _params) {
        deploymentTimestamp = block.timestamp;
        targetAverageAgeSeconds = _params.targetAverageAgeSeconds;
        accrualParameter = _params.initialAccrualParameter;
        minimumAccrualParameter = _params.minimumAccrualParameter;
        require(minimumAccrualParameter > 0, "CBM: Min accrual parameter cannot be zero");
        accrualAdjustmentMultiplier = 1e18 - _params.accrualAdjustmentRate;
        accrualAdjustmentPeriodSeconds = _params.accrualAdjustmentPeriodSeconds;
        //curveLiquidityGauge = ICurveLiquidityGaugeV5(_externalContractAddresses.curveLiquidityGaugeAddress); // needed?
        CHICKEN_IN_AMM_FEE = _params.chickenInAMMFee;
        //uint256 fee = curvePool.fee(); // This is practically immutable (can only be set once, in `initialize()`)
        BOOTSTRAP_PERIOD_CHICKEN_IN = _params.bootstrapPeriodChickenIn;
        BOOTSTRAP_PERIOD_REDEEM = _params.bootstrapPeriodRedeem;
        MIN_BROOT_SUPPLY = _params.minbRootSupply;
        require(_params.minBondAmount > 0, "CBM: MIN BOND AMOUNT parameter cannot be zero"); // We can still use 1e-18
        MIN_BOND_AMOUNT = _params.minBondAmount;
        BETA = _params.redemptionFeeBeta;
        MINUTE_DECAY_FACTOR = _params.redemptionFeeMinuteDecayFactor;
        //max approvals
        rootToken.approve(address(curveLiquidityGauge), MAX_UINT256);
        rootToken.approve(address(beanstalk), MAX_UINT256);
    }

    // --- User-facing functions ---

    // Farmer deposits Root, gets an claim via an NFT
    // Root can be from circulating balances, or in the farmer balances
    // BALANCE MUST BE INTERNAL, USE PIPELINE TO BRING IT TO INTERNAL
    function createBond(
        uint256 _amount 
    ) public returns (uint256) {
        //check requires
        _requireMinBond(_amount);
        _requireMigrationNotActive();
        _updateAccrualParameter();

        // Mint the bond NFT to the caller and get the bond ID
        (uint256 bondID) = bondNFT.mint(msg.sender);
        
        // create BondData Struct
        BondData memory bondData;
        bondData.amount = uint112(_amount);
        bondData.rootBDV = uint96(rootToken.bdvPerRoot());
        bondData.startTime = uint40(block.timestamp);
        bondData.status = BondStatus.active;
        idToBondData[bondID] = bondData;
        
        //update pending and transfer Roots
        totalWeightedStartTimes += _amount * block.timestamp; 
        rootBucket.pending += _amount;
        beanstalk.transferInternalTokenFrom(
            IERC20(rootToken), 
            msg.sender, 
            address(this), 
            _amount, 
            To.INTERNAL
        );

        emit BondCreated(msg.sender, bondID, _amount);
        return bondID;
    }

    // TODO:
    function createBondWithPermit(
        address owner, 
        uint256 amount, 
        uint256 deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) external returns (uint256) {
        IRoot asset;
        asset = rootToken;
        if (asset.allowance(owner, address(this)) < amount) {
            asset.permit(owner, address(this), amount, deadline, v, r, s);
        }
        return createBond(amount);
    }

    // Farmer chickens out, forfeiting yield and the claim to bRoot.
    function chickenOut(uint256 _bondID, uint256 _minROOT, To toMode) external {
        BondData memory bond = idToBondData[_bondID];

        _requireCallerOwnsBond(_bondID);
        _requireActiveStatus(bond.status);

        _updateAccrualParameter();

        idToBondData[_bondID].status = BondStatus.chickenedOut;
        idToBondData[_bondID].endTime = uint40(block.timestamp);

        // uint80 newDna = bondNFT.setFinalExtraData(
        //     msg.sender, 
        //     _bondID,  
        //     rootBucket.permanent / NFT_RANDOMNESS_DIVISOR
        // );
        countChickenOut += 1;

        // calculate the ratio of current rootBDV to rootBDV when bonded
        uint256 RootBDVRatio = bondBDVRatio(bond.rootBDV);

        // reduce the ROOT token given back equal to the ratio.
        // cknAmt/bond.amount = rootBdvAtBond/currentBDV
        uint256 cknAmount = RootBDVRatio * uint256(bond.amount) / 1e18;
        require(_minROOT >= cknAmount, "CBM: root gained is less than minROOT");
        totalWeightedStartTimes -= bond.amount * bond.startTime;
        rootBucket.pending -= bond.amount;
        rootBucket.reserve += uint160(bond.amount - cknAmount);

        //transfer to user wallet, internal or external
        beanstalk.transferInternalTokenFrom(
            IERC20(rootToken), 
            address(this), 
            msg.sender,
            cknAmount, 
            toMode
        );
        
        emit BondCancelled(msg.sender, _bondID, cknAmount);
    }

    // Transfers ROOT to the bRoot/ROOT AMM LP Rewards staking contract.
    function transferToCurve(uint256 rootTokenToTransfer) internal {

        // Transfer roots from internal balances to external balances
        beanstalk.transferInternalTokenFrom(
            IERC20(rootToken), 
            address(this), 
            address(this),
            rootTokenToTransfer, 
            To.EXTERNAL
        );
        // deposit into liquidty reward
        curveLiquidityGauge.deposit_reward_token(ROOTTOKEN, rootTokenToTransfer);
    }

    // Farmer chickens in, forfeiting the claim to inital deposit, and gains bRoot.
    function chickenIn(uint256 _bondID) external {
        BondData memory bond = idToBondData[_bondID];

        _requireCallerOwnsBond(_bondID);
        _requireActiveStatus(bond.status);

        uint256 updatedAccrualParameter = _updateAccrualParameter();
        // calculate the yield gained, to allocate towards reserve
        uint256 RootBDVRatio = bondBDVRatio(bond.rootBDV);
        uint256 cknAmount = RootBDVRatio * uint256(bond.amount) / 1e18;
        uint256 yield = bond.amount - cknAmount;
        (uint256 chickenInFeeAmount, uint256 bondAmountMinusChickenInFee) = _getBondWithChickenInFeeApplied(cknAmount);

        /* Upon the first chicken-in after a) system deployment or b) redemption of the full bRoot supply, divert
        * any earned yield to the bRoot-LUSD AMM for fairness.
        * This is not done in migration mode since there is no need to send rewards to the staking contract.
        */
        if (bRoot.totalSupply() == 0 && !migration) {
            require(block.timestamp >= bond.startTime + BOOTSTRAP_PERIOD_CHICKEN_IN, "CBM: First chicken in must wait until bootstrap period is over");
            firstChickenInTime = block.timestamp;
            transferToCurve(yield);
            // since yield is given to curve, none is given to reserve
            // so first chickenIn gives 3% + yield to curve
            yield = 0;
        }

        // Get the ROOT amount to acquire from the bond in proportion to the system's current backing ratio, in order to maintain said ratio.
        uint256 rootToAcquire = _calcAccruedAmount(bond.startTime, bondAmountMinusChickenInFee, updatedAccrualParameter);
        // Get backing ratio and accrued bBEAN
        uint256 backingRatio = calcSystemBackingRatio();
        uint256 accruedBRoot = rootToAcquire * 1e18 / backingRatio;

        idToBondData[_bondID].claimedBRoot = uint216(Math.min(accruedBRoot / 1e18, type(uint216).max)); // to units and uint64
        idToBondData[_bondID].status = BondStatus.chickenedIn;
        idToBondData[_bondID].endTime = uint40(block.timestamp);
        // uint256 permanentBucket = 
        //     rootToken.balanceOf(address(this)) 
        //     - rootBucket.pending 
        //     - rootBucket.reserve;
        //uint80 newDna = bondNFT.setFinalExtraData(msg.sender, _bondID, permanentBucket / NFT_RANDOMNESS_DIVISOR);

        countChickenIn += 1;

        // subtract from pending, add to reserve
        // implicitly adds to permanent
        rootBucket.pending -= bond.amount;
        rootBucket.reserve += uint160(rootToAcquire + yield);
        totalWeightedStartTimes -= bond.amount * bond.startTime;
        uint256 rootSurplus;
        // Transfer the chicken in fee to the LUSD/bRoot AMM LP Rewards staking contract during normal mode.
        // In migration mode, transfer surplus back to bonder
        if (!migration) { 
            transferToCurve(chickenInFeeAmount);
        } else {
            // Get the remaining surplus from the LUSD amount to acquire from the bond
            rootSurplus = bondAmountMinusChickenInFee - rootToAcquire; 
                if (rootSurplus > 0) {
                beanstalk.transferInternalTokenFrom(
                    IERC20(rootToken),  
                    address(this),
                    msg.sender, 
                    rootSurplus, 
                    To.INTERNAL
                );
            }
        }
        bRoot.mint(msg.sender, accruedBRoot);           
        // TODO: convert season deposit with the reserve season, 
        emit BondClaimed(msg.sender, _bondID, bond.amount, accruedBRoot, rootSurplus, chickenInFeeAmount, migration);
    }

    // Farmer redeems Root for bRoot. 
    function redeem(uint256 _bRootToRedeem, To toMode) external returns (uint256) {
        _requireNonZeroAmount(_bRootToRedeem);
        _requireRedemptionNotDepletingbRoot(_bRootToRedeem);

        require(block.timestamp >= firstChickenInTime + BOOTSTRAP_PERIOD_REDEEM, "CBM: Redemption after first chicken in must wait until bootstrap period is over");


        uint256 fractionOfBRootToRedeem = _bRootToRedeem * 1e18 / bRoot.totalSupply();
        
        // I believe this changes the alpha, but not sure how this works with the redemption fee
        //uint256 redemptionFeePercentage = migration ? 0 : _updateRedemptionFeePercentage(fractionOfBRootToRedeem);
        
        _requireNonZeroAmount(rootBucket.reserve);

        // Burn the redeemed bRoot
        bRoot.burn(msg.sender, _bRootToRedeem);

        uint256 reserveRootToRedeem = rootBucket.reserve * fractionOfBRootToRedeem / 1e18;

        if (reserveRootToRedeem > 0){
            beanstalk.transferInternalTokenFrom(
                IERC20(rootToken),
                address(this), 
                msg.sender, 
                reserveRootToRedeem, 
                toMode
            );
        }             


        rootBucket.reserve -= uint160(reserveRootToRedeem);
        emit BRootRedeemed(msg.sender, _bRootToRedeem, reserveRootToRedeem);

        return (reserveRootToRedeem);
    }
    
    /// @dev harvest takes the yield from the permanent pool and gives it to the reserve
    /// this does not that yield from the pending as it is calculated per bond basis 
    function harvest() external {
        require(firstChickenInTime != 0);
        uint256 total = rootToken.balanceOf(address(this));
        uint256 permanent = total - rootBucket.pending - rootBucket.reserve;
        uint256 RootBDVRatio = bondBDVRatio(rootBucket.lastBDV);
        
        // add yield to reserve bucket
        // this implicitly removes from the permanent
        rootBucket.reserve += uint160(permanent - RootBDVRatio * permanent/1e18);
    }

    // outputs the ratio of the bond BDV and the current root BDV
    function bondBDVRatio(uint256 rootBDV) internal view returns (uint256){
        uint256 currentBDV = rootToken.bdvPerRoot();
        return rootBDV * 1e18 / currentBDV;
    }

    // --- Migration functionality ---

    /* Migration function callable one-time and only by beanSprout governance.
    */
    // TODO: think about how we should handle this? maybe transfer permanent to Gnosis (like bean sprout gnosis)
    function activateMigration() external {
        _requireMigrationNotActive();
        migration = true;
        uint256 total = rootToken.balanceOf(address(this));
        uint256 permanent = total - rootBucket.pending - rootBucket.reserve;
        emit MigrationTriggered(permanent);
    }

    function transferPermanentToBeanSprout(uint256 _amount) external {
        _requireCallerIsBeanSproutGovernance();
        if (migration) {
            beanstalk.transferInternalTokenFrom(
                IERC20(rootToken), 
                address(this), 
                BSM,
                _amount, 
                To.INTERNAL
            );
        }

    }

    function changeChickenInFee(uint256 fee) external {
         _requireCallerIsBeanSproutGovernance();
        require(fee < 1e6); // cannot exceed 100% you monster
        CHICKEN_IN_AMM_FEE = fee;
    }



    // Calc decayed redemption rate
    /// note: no fees, functions not needed
    function calcRedemptionFeePercentage(uint256 _fractionOfbRootToRedeem) public view returns (uint256) {
        uint256 minutesPassed = _minutesPassedSinceLastRedemption();
        uint256 decayFactor = decPow(MINUTE_DECAY_FACTOR, minutesPassed);

        uint256 decayedBaseRedemptionRate = baseRedemptionRate * decayFactor / DECIMAL_PRECISION;

        // Increase redemption base rate with the new redeemed amount
        uint256 newBaseRedemptionRate = decayedBaseRedemptionRate + _fractionOfbRootToRedeem / BETA;
        newBaseRedemptionRate = Math.min(newBaseRedemptionRate, DECIMAL_PRECISION); // cap baseRate at a maximum of 100%
        //assert(newBaseRedemptionRate <= DECIMAL_PRECISION); // This is already enforced in the line above

        return newBaseRedemptionRate;
    }

    // Update the base redemption rate and the last redemption time (only if time passed >= decay interval. This prevents base rate griefing)
    function _updateRedemptionFeePercentage(uint256 _fractionOfbRootToRedeem) internal returns (uint256) {
        uint256 newBaseRedemptionRate = calcRedemptionFeePercentage(_fractionOfbRootToRedeem);
        baseRedemptionRate = newBaseRedemptionRate;
        emit BaseRedemptionRateUpdated(newBaseRedemptionRate);

        uint256 timePassed = block.timestamp - lastRedemptionTime;

        if (timePassed >= SECONDS_IN_ONE_MINUTE) {
            lastRedemptionTime = block.timestamp;
            emit LastRedemptionTimeUpdated(block.timestamp);
        }

        return newBaseRedemptionRate;
    }

    function _minutesPassedSinceLastRedemption() internal view returns (uint256) {
        return (block.timestamp - lastRedemptionTime) / SECONDS_IN_ONE_MINUTE;
    }

    function _getBondWithChickenInFeeApplied(uint256 _bondRootAmount) internal view returns (uint256, uint256) {
        // Apply zero fee in migration mode
        if (migration) {return (0, _bondRootAmount);}

        // Otherwise, apply the constant fee rate
        uint256 chickenInFeeAmount = _bondRootAmount * CHICKEN_IN_AMM_FEE / 1e18;
        uint256 bondAmountMinusChickenInFee = _bondRootAmount - chickenInFeeAmount;

        return (chickenInFeeAmount, bondAmountMinusChickenInFee);
    }

    function _getBondAmountMinusChickenInFee(uint256 _bondRootAmount) internal view returns (uint256) {
        (, uint256 bondAmountMinusChickenInFee) = _getBondWithChickenInFeeApplied(_bondRootAmount);
        return bondAmountMinusChickenInFee;
    }

    /* _calcAccruedAmount: internal getter for calculating accrued token amount for a given bond.
    *
    * This function is unit-agnostic. It can be used to calculate a bonder's accrrued bRoot, or the Root that that the
    * CB system would acquire (i.e. receive to the acquired bucket) if the bond were Chickened In now.
    *
    * For the bonder, _capAmount is their bRoot cap.
    * For the CB system, _capAmount is the ROOT bond amount (less the Chicken In fee).
    */
    function _calcAccruedAmount(uint256 _startTime, uint256 _capAmount, uint256 _accrualParameter) internal view returns (uint256) {
        // All bonds have a non-zero creation timestamp, so return accrued sLQTY 0 if the startTime is 0
        if (_startTime == 0) {return 0;}

        // Scale `bondDuration` up to an 18 digit fixed-point number.
        // This lets us add it to `accrualParameter`, which is also an 18-digit FP.
        uint256 bondDuration = 1e18 * (block.timestamp - _startTime);

        uint256 accruedAmount = _capAmount * bondDuration / (bondDuration + _accrualParameter);
        //assert(accruedAmount < _capAmount); // we leave it as a comment so we can uncomment it for automated testing tools

        return accruedAmount;
    }

    // Gauge the average (size-weighted) outstanding bond age and adjust accrual parameter if it's higher than our target.
    // If there's been more than one adjustment period since the last adjustment, perform multiple adjustments retroactively.
    function _calcUpdatedAccrualParameter(
        uint256 _storedAccrualParameter,
        uint256 _storedAccrualAdjustmentCount
    )
        internal
        view
        returns (
            uint256 updatedAccrualParameter,
            uint256 updatedAccrualAdjustmentPeriodCount
        )
    {
        updatedAccrualAdjustmentPeriodCount = (block.timestamp - deploymentTimestamp) / accrualAdjustmentPeriodSeconds;

        if (
            // There hasn't been enough time since the last update to warrant another update
            updatedAccrualAdjustmentPeriodCount == _storedAccrualAdjustmentCount ||
            // or `accrualParameter` is already bottomed-out
            _storedAccrualParameter == minimumAccrualParameter ||
            // or there are no outstanding bonds (avoid division by zero)
            rootBucket.pending == 0
        ) {
            return (_storedAccrualParameter, updatedAccrualAdjustmentPeriodCount);
        }

        uint256 averageStartTime = totalWeightedStartTimes / rootBucket.pending;

        // We want to calculate the period when the average age will have reached or exceeded the
        // target average age, to be used later in a check against the actual current period.
        //
        // At any given timestamp `t`, the average age can be calculated as:
        //   averageAge(t) = t - averageStartTime
        //
        // For any period `n`, the average age is evaluated at the following timestamp:
        //   tSample(n) = deploymentTimestamp + n * accrualAdjustmentPeriodSeconds
        //
        // Hence we're looking for the smallest integer `n` such that:
        //   averageAge(tSample(n)) >= targetAverageAgeSeconds
        //
        // If `n` is the smallest integer for which the above inequality stands, then:
        //   averageAge(tSample(n - 1)) < targetAverageAgeSeconds
        //
        // Combining the two inequalities:
        //   averageAge(tSample(n - 1)) < targetAverageAgeSeconds <= averageAge(tSample(n))
        //
        // Substituting and rearranging:
        //   1.    deploymentTimestamp + (n - 1) * accrualAdjustmentPeriodSeconds - averageStartTime
        //       < targetAverageAgeSeconds
        //      <= deploymentTimestamp + n * accrualAdjustmentPeriodSeconds - averageStartTime
        //
        //   2.    (n - 1) * accrualAdjustmentPeriodSeconds
        //       < averageStartTime + targetAverageAgeSeconds - deploymentTimestamp
        //      <= n * accrualAdjustmentPeriodSeconds
        //
        //   3. n - 1 < (averageStartTime + targetAverageAgeSeconds - deploymentTimestamp) / accrualAdjustmentPeriodSeconds <= n
        //
        // Using equivalence `n = ceil(x) <=> n - 1 < x <= n` we arrive at:
        //   n = ceil((averageStartTime + targetAverageAgeSeconds - deploymentTimestamp) / accrualAdjustmentPeriodSeconds)
        //
        // We can calculate `ceil(a / b)` using `Math.ceilDiv(a, b)`.
        uint256 adjustmentPeriodCountWhenTargetIsExceeded = Math.ceilDiv(
            averageStartTime + targetAverageAgeSeconds - deploymentTimestamp,
            accrualAdjustmentPeriodSeconds
        );

        if (updatedAccrualAdjustmentPeriodCount < adjustmentPeriodCountWhenTargetIsExceeded) {
            // No adjustment needed; target average age hasn't been exceeded yet
            return (_storedAccrualParameter, updatedAccrualAdjustmentPeriodCount);
        }

        uint256 numberOfAdjustments = updatedAccrualAdjustmentPeriodCount - Math.max(
            _storedAccrualAdjustmentCount,
            adjustmentPeriodCountWhenTargetIsExceeded - 1
        );

        updatedAccrualParameter = Math.max(
            _storedAccrualParameter * decPow(accrualAdjustmentMultiplier, numberOfAdjustments) / 1e18,
            minimumAccrualParameter
        );
    }

    function _updateAccrualParameter() internal returns (uint256) {
        uint256 storedAccrualParameter = accrualParameter;
        uint256 storedAccrualAdjustmentPeriodCount = accrualAdjustmentPeriodCount;

        (uint256 updatedAccrualParameter, uint256 updatedAccrualAdjustmentPeriodCount) =
            _calcUpdatedAccrualParameter(storedAccrualParameter, storedAccrualAdjustmentPeriodCount);

        if (updatedAccrualAdjustmentPeriodCount != storedAccrualAdjustmentPeriodCount) {
            accrualAdjustmentPeriodCount = updatedAccrualAdjustmentPeriodCount;

            if (updatedAccrualParameter != storedAccrualParameter) {
                accrualParameter = updatedAccrualParameter;
                emit AccrualParameterUpdated(updatedAccrualParameter);
            }
        }

        return updatedAccrualParameter;
    }

    // Internal getter for calculating the bond bRoot cap based on bonded amount and backing ratio
    function _calcBondBRootCap(uint256 _bondedAmount, uint256 _backingRatio) internal pure returns (uint256) {
        return _bondedAmount * 1e18 / _backingRatio;
    }

    // --- 'require' functions

    function _requireCallerOwnsBond(uint256 _bondID) internal view {
        require(msg.sender == bondNFT.ownerOf(_bondID), "CBM: Caller must own the bond");
    }

    function _requireActiveStatus(BondStatus status) internal pure {
        require(status == BondStatus.active, "CBM: Bond must be active");
    }

    function _requireNonZeroAmount(uint256 _amount) internal pure {
        require(_amount > 0, "CBM: Amount must be > 0");
    }

    function _requireNonZeroBBEANSupply() internal view {
        require(bRoot.totalSupply() > 0, "CBM: bRoot Supply must be > 0 upon shifting");
    }

    function _requireMinBond(uint256 _beanAmount) internal view {
        require(_beanAmount >= MIN_BOND_AMOUNT, "CBM: Bond minimum amount not reached");
    }

    // should we keep this?
    function _requireRedemptionNotDepletingbRoot(uint256 _bRootToRedeem) internal view {
        if (!migration) {
            //require(_bRootToRedeem < bRootTotalSupply, "CBM: Cannot redeem total supply");
            require(_bRootToRedeem + MIN_BROOT_SUPPLY <= bRoot.totalSupply(), "CBM: Cannot redeem below min supply");
        }
    }

    function _requireMigrationNotActive() internal view {
        require(!migration, "CBM: Migration must be not be active");
    }
    
    function _requireCallerIsBeanSproutGovernance() internal view {
        require(msg.sender == BSM, "CBM: Only BSM can call");
    }
    // --- Getter convenience functions ---

    // Bond getters

    function getBondData(uint256 _bondID)
        external
        view
        returns (
            BondData memory bond
        )
    {
       return idToBondData[_bondID];
        //return (bond.amount, bond.rootBDV, bond.startTime, uint8(bond.status), bond.endTime, bond.claimedBRoot);
    }

    // outputs how much ROOT that would be allocated to reserve bucket
    function getRootToAcquire(uint256 _bondID) external view returns (uint256) {
        BondData memory bond = idToBondData[_bondID];
        (uint256 updatedAccrualParameter, ) = _calcUpdatedAccrualParameter(accrualParameter, accrualAdjustmentPeriodCount);

        return _calcAccruedAmount(bond.startTime, _getBondAmountMinusChickenInFee(bond.amount), updatedAccrualParameter);
    }

    // output the bRoot currently accrued
    function calcAccruedBRoot(uint256 _bondID) external view returns (uint256) {
        BondData memory bond = idToBondData[_bondID];

        if (bond.status != BondStatus.active) {
            return 0;
        }

        uint256 bondBRootCap = _calcBondBRootCap(_getBondAmountMinusChickenInFee(bond.amount), calcSystemBackingRatio());
        (uint256 updatedAccrualParameter, ) = _calcUpdatedAccrualParameter(accrualParameter, accrualAdjustmentPeriodCount);

        return _calcAccruedAmount(bond.startTime, bondBRootCap, updatedAccrualParameter);
    }

    // outputs the maximum bRoot given bondID
    function calcBondBRootCap(uint256 _bondID) external view returns (uint256) {
        uint256 backingRatio = calcSystemBackingRatio();
        BondData memory bond = idToBondData[_bondID];
        return _calcBondBRootCap(_getBondAmountMinusChickenInFee(bond.amount), backingRatio);
    }

    // outputs the backing ratio (roots in reserve / )
    function calcSystemBackingRatio() public view returns (uint256) {
        uint256 totalBRootSupply = bRoot.totalSupply();
        // before the first chickenIn, return a backing ratio of 1.
        // also when the bRoot supply is fully redeemed.
        if (totalBRootSupply == 0) return 1e18;
        return  rootBucket.reserve * 1e18  / totalBRootSupply;
    }

    function calcUpdatedAccrualParameter() external view returns (uint256) {
        (uint256 updatedAccrualParameter, ) = _calcUpdatedAccrualParameter(accrualParameter, accrualAdjustmentPeriodCount);
        return updatedAccrualParameter;
    }

    function getOpenBondCount() external view returns (uint256 openBondCount) {
        return bondNFT.totalSupply() - countChickenIn - countChickenOut;
    }

    function getReserves() external view returns(uint256,uint160,uint96,uint256) {
        BucketData memory tmpRootBucket = rootBucket;
        uint256 permanent = rootToken.balanceOf(address(this)) - tmpRootBucket.pending - tmpRootBucket.reserve;
        return(
            tmpRootBucket.pending,
            tmpRootBucket.reserve,
            tmpRootBucket.lastBDV,
            permanent
        );
    }

    function permanentRoot() external view returns (uint256) {
        BucketData memory tmpRootBucket = rootBucket;
        return rootToken.balanceOf(address(this)) - tmpRootBucket.pending - tmpRootBucket.reserve;
    }

    function totalAcquiredRoot() external view returns (uint256) {
        return rootToken.balanceOf(address(this));
    }

    function pendingRoot() external view returns (uint256){
        BucketData memory tmpRootBucket = rootBucket;
        return tmpRootBucket.pending;
    }


}