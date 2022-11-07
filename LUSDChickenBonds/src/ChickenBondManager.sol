// SPDX-License-Identifier: GPL-3.0
pragma solidity <0.8.10;

import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./utils/ChickenMath.sol";

import "./Interfaces/IBondNFT.sol";
import "./Interfaces/IBEANToken.sol";
import "./Interfaces/IBBEANToken.sol";
import "./Interfaces/IBAMM.sol";
import "./Interfaces/IYearnVault.sol";
import "./Interfaces/ICurvePool.sol";
import "./Interfaces/IYearnRegistry.sol";
import "./Interfaces/IBeanstalk.sol";
import "./Interfaces/IChickenBondManager.sol";
import "./Interfaces/ICurveLiquidityGaugeV5.sol";

import {LibConvertData} from "Beanstalk/Convert/LibConvertData.sol";

// import "forge-std/console.sol";

// current todos: 
// 1 bean3crv != 1.00 USDC or BDV, due to the fact that fees are accured in the bean3crv token, so this will need to b accounted for

contract ChickenBondManager is ChickenMath, IChickenBondManager {

    // ChickenBonds contracts and addresses
    IBondNFT immutable public bondNFT;

    /// done check interfaces for IBLUSD and ILUSD -> Convert to IBBEAN, IBEAN
    IBBEANToken immutable public bBEANToken;
    IBEANToken immutable public beanToken; 
    IBEANToken immutable public bean3CRVToken; 


    // TODO: remove bammSPVault,yearnCurveVault,yearnRegistry with beanstalk address (Yield gained there)
    // External contracts and addresses
    ICurvePool immutable public curvePool; // LUSD meta-pool (i.e. coin 0 is LUSD, coin 1 is LP token from a base pool)
    ICurvePool immutable public curveBasePool; // base pool of curvePool
    IBAMM immutable public bammSPVault; // B.Protocol Stability Pool vault
    IYearnVault immutable public yearnCurveVault;
    IYearnRegistry immutable public yearnRegistry;
    ICurveLiquidityGaugeV5 immutable public curveLiquidityGauge;
    IBeanstalk immutable public beanstalk;

    address immutable public BeanstalkFarmsMultisig;

    // TODO: determine if needed for beanstalk (3% in liquity)
    // the chicken in fee incentivizes bBEAN-BEAN3CRV LP 
    // the fee could be removed in a couple of ways: 
    // 1: We add bBEAN-BEAN3CRV as a whitelisted asset in the silo for 2 seeds or so
    // 2: We ask bean sprout for a grant for the fee
    uint256 immutable public CHICKEN_IN_AMM_FEE;

    // we store the bucket amts explictly for both bean and bean3crv, as it is non trivial 
    // to obtain a Farmer token deposits on chain.

    BucketData public beanBuckets;
    BucketData public bean3CrvBuckets;
    
    // --- Data structures ---

    // TODO: remove unneeded addresses
    struct ExternalAdresses {
        address bondNFTAddress;
        address beanTokenAddress;
        address curvePoolAddress;
        address curveBasePoolAddress;
        address BeanstalkFarmsMultisig;
        address bLUSDTokenAddress;
        address curveLiquidityGaugeAddress;
    }
    // TODO: believe this can be more easily packed
    struct Params {
        uint256 targetAverageAgeSeconds;        // Average outstanding bond age above which the controller will adjust `accrualParameter` in order to speed up accrual
        uint256 initialAccrualParameter;        // Initial value for `accrualParameter`
        uint256 minimumAccrualParameter;        // Stop adjusting `accrualParameter` when this value is reached
        uint256 accrualAdjustmentRate;          // `accrualParameter` is multiplied `1 - accrualAdjustmentRate` every time there's an adjustment
        uint256 accrualAdjustmentPeriodSeconds; // The duration of an adjustment period in seconds
        uint256 chickenInAMMFee;                // Fraction of bonded amount that is sent to Curve Liquidity Gauge to incentivize LUSD-bLUSD liquidity
        uint256 curveDepositDydxThreshold;      // Threshold of SP => Curve shifting
        uint256 curveWithdrawalDxdyThreshold;   // Threshold of Curve => SP shifting
        uint256 bootstrapPeriodChickenIn;       // Min duration of first chicken-in
        uint256 bootstrapPeriodRedeem;          // Redemption lock period after first chicken in
        uint256 bootstrapPeriodShift;           // Period after launch during which shifter functions are disabled
        uint256 shifterDelay;                   // Duration of shifter countdown
        uint256 shifterWindow;                  // Interval in which shifting is possible after countdown finishes
        uint256 minBLUSDSupply;                 // Minimum amount of bLUSD supply that must remain after a redemption
        uint256 minBondAmount;                  // Minimum amount of LUSD that needs to be bonded
        uint256 nftRandomnessDivisor;           // Divisor for permanent LUSD amount in NFT pseudo-randomness computation (see comment below)
        //uint256 redemptionFeeBeta;              // Parameter by which to divide the redeemed fraction, in order to calculate the new base rate from a redemption
        //uint256 redemptionFeeMinuteDecayFactor; // Factor by which redemption fee decays (exponentially) every minute
    }
    
    // TODO: see above
    // packed into one slot for gas savings 
    struct BondData {
        uint128 amount; // very unlikely that a bond will contain > uint128.max
        uint48 claimedBBEAN; //  very unlikely that a bond will redeem > uint48.max bBEAN, without decimals
        uint48 startTime; // uint48 is more than big enough to store
        uint48 endTime; // same as above
        uint32 season; // season in which deposit 
        BondStatus status; // 
        TokenType token; // token that was bonded (bean or bean3crv)
    }
    
    enum TokenType {
        BEAN,
        BEAN3CRV
    }

    // @dev we store the season of deposits in the bond NFT, as during a chicken out, we must account
    // the season they deposit in
    // uint224 as amt and season are updated at the same time
    struct BucketData { 
        uint256 pendingAmt; // the amount of an given asset in the pending Bucket 
        uint224 reserveAmt; // the amount of an given asset in the reserve Bucket 
        uint32 reserveSeason; // the season that the reserveAmt is deposited in beanstalk
        uint224 permenentAmt; // the amount of an given asset in the permenent Bucket 
        uint32 permanentSeason;  // the season that the permenentAmt is deposited in beanstalk
    }

    uint256 public firstChickenInTime; // Timestamp of the first chicken in after bLUSD supply is zero
    uint256 public totalWeightedStartTimes; // Sum of `beanAmount * startTime` for all outstanding bonds (used to tell weighted average bond age)
    uint256 public lastRedemptionTime; // The timestamp of the latest redemption
    uint256 public baseRedemptionRate; // The latest base redemption rate
    mapping (uint256 => BondData) private idToBondData;

    /* migration: flag which determines whether the system is in migration mode.

    When migration mode has been triggered:

    - No funds are held in the permanent bucket. Liquidity is either pending, or acquired
    /// TODO: do we wanna change this?
    - Bond creation and public shifter functions are disabled
    - Users with an existing bond may still chicken in or out
    - Chicken-ins will no longer send the LUSD surplus to the permanent bucket. Instead, they refund the surplus to the bonder
    - bLUSD holders may still redeem
    - Redemption fees are zero
    */
    bool public migration;
    

    uint256 public countChickenIn;
    uint256 public countChickenOut;
    // --- Constants ---

    uint256 constant MAX_UINT256 = type(uint256).max;
    int128 public constant INDEX_OF_LUSD_TOKEN_IN_CURVE_POOL = 0;
    int128 constant INDEX_OF_3CRV_TOKEN_IN_CURVE_POOL = 1;

    uint256 constant public SECONDS_IN_ONE_MINUTE = 60;

    uint256 public immutable BOOTSTRAP_PERIOD_CHICKEN_IN; // Min duration of first chicken-in
    uint256 public immutable BOOTSTRAP_PERIOD_REDEEM;     // Redemption lock period after first chicken in
    uint256 public immutable BOOTSTRAP_PERIOD_SHIFT;      // Period after launch during which shifter functions are disabled

    uint256 public immutable SHIFTER_DELAY;               // Duration of shifter countdown
    uint256 public immutable SHIFTER_WINDOW;              // Interval in which shifting is possible after countdown finishes

    uint256 public immutable MIN_BBEAN_SUPPLY;            // Minimum amount of bLUSD supply that must remain after a redemption
    uint256 public immutable MIN_BOND_AMOUNT;             // Minimum amount of LUSD that needs to be bonded
    // This is the minimum amount the permanent bucket needs to be increased by an attacker (through previous chicken in or redemption fee),
    // in order to manipulate the obtained NFT. If the attacker finds the desired outcome at attempt N,
    // the permanent increase should be N * NFT_RANDOMNESS_DIVISOR.
    // It also means that as long as Permanent doesn’t change in that order of magnitude, attacker can try to manipulate
    // only changing the event date.
    uint256 public immutable NFT_RANDOMNESS_DIVISOR;

    /*
     * BETA: 18 digit decimal. Parameter by which to divide the redeemed fraction, in order to calc the new base rate from a redemption.
     * Corresponds to (1 / ALPHA) in the Liquity white paper.
     */
    uint256 public immutable BETA;
    uint256 public immutable MINUTE_DECAY_FACTOR;

    uint256 constant CURVE_FEE_DENOMINATOR = 1e10;

    // Thresholds of SP <=> Curve shifting
    uint256 public immutable curveDepositBEAN3CRVExchangeRateThreshold;
    uint256 public immutable curveWithdrawalBEAN3CRVExchangeRateThreshold;

    // Timestamp at which the last shifter countdown started
    uint256 public lastShifterCountdownStartTime;

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
    event BondCreated(address indexed bonder, uint256 bondId,uint8 Token, uint256 amount, uint80 bondInitialHalfDna);
    event BondClaimed(
        address indexed bonder,
        uint256 bondId,
        uint256 beanAmount,
        uint256 bLusdAmount,
        uint256 beanSurplus,
        uint256 chickenInFeeAmount,
        bool migration,
        uint80 bondFinalHalfDna
    );
    event BondCancelled(address indexed bonder, uint256 bondId, uint256 withdrawnLusdAmount, uint80 bondFinalHalfDna);
    event BBEANRedeemed(address indexed redeemer, uint256 bLusdAmount, uint256 beanAmount, uint256 bean3CRVAmount);
    event MigrationTriggered(uint256 previousPermanentLUSD);
    event AccrualParameterUpdated(uint256 accrualParameter);

    // --- Constructor ---

    constructor
    (
        ExternalAdresses memory _externalContractAddresses, // to avoid stack too deep issues
        Params memory _params
    )
    {
        bondNFT = IBondNFT(_externalContractAddresses.bondNFTAddress);
        beanToken = IBEANToken(_externalContractAddresses.beanTokenAddress);
        bBEANToken = IBBEANToken(_externalContractAddresses.bLUSDTokenAddress);
        curvePool = ICurvePool(_externalContractAddresses.curvePoolAddress);
        curveBasePool = ICurvePool(_externalContractAddresses.curveBasePoolAddress);
        BeanstalkFarmsMultisig = _externalContractAddresses.BeanstalkFarmsMultisig;

        deploymentTimestamp = block.timestamp;
        targetAverageAgeSeconds = _params.targetAverageAgeSeconds;
        accrualParameter = _params.initialAccrualParameter;
        minimumAccrualParameter = _params.minimumAccrualParameter;
        require(minimumAccrualParameter > 0, "CBM: Min accrual parameter cannot be zero");
        accrualAdjustmentMultiplier = 1e18 - _params.accrualAdjustmentRate;
        accrualAdjustmentPeriodSeconds = _params.accrualAdjustmentPeriodSeconds;

        curveLiquidityGauge = ICurveLiquidityGaugeV5(_externalContractAddresses.curveLiquidityGaugeAddress); // needed?
        CHICKEN_IN_AMM_FEE = _params.chickenInAMMFee;

        uint256 fee = curvePool.fee(); // This is practically immutable (can only be set once, in `initialize()`)

        // By exchange rate, we mean the rate at which Curve exchanges LUSD <=> $ value of 3CRV (at the virtual price),
        // which is reduced by the fee.
        // For convenience, we want to parameterize our thresholds in terms of the spot prices -dy/dx & -dx/dy,
        // which are not exposed by Curve directly. Instead, we turn our thresholds into thresholds on the exchange rate
        // by taking into account the fee.
        curveDepositBEAN3CRVExchangeRateThreshold =
            _params.curveDepositDydxThreshold * (CURVE_FEE_DENOMINATOR - fee) / CURVE_FEE_DENOMINATOR;
        curveWithdrawalBEAN3CRVExchangeRateThreshold =
            _params.curveWithdrawalDxdyThreshold * (CURVE_FEE_DENOMINATOR - fee) / CURVE_FEE_DENOMINATOR;

        BOOTSTRAP_PERIOD_CHICKEN_IN = _params.bootstrapPeriodChickenIn;
        BOOTSTRAP_PERIOD_REDEEM = _params.bootstrapPeriodRedeem;
        BOOTSTRAP_PERIOD_SHIFT = _params.bootstrapPeriodShift;
        SHIFTER_DELAY = _params.shifterDelay;
        SHIFTER_WINDOW = _params.shifterWindow;
        MIN_BBEAN_SUPPLY = _params.minBLUSDSupply;
        require(_params.minBondAmount > 0, "CBM: MIN BOND AMOUNT parameter cannot be zero"); // We can still use 1e-18
        MIN_BOND_AMOUNT = _params.minBondAmount;
        NFT_RANDOMNESS_DIVISOR = _params.nftRandomnessDivisor;
        BETA = _params.redemptionFeeBeta;
        MINUTE_DECAY_FACTOR = _params.redemptionFeeMinuteDecayFactor;

        beanToken.approve(address(curvePool), MAX_UINT256); 
        beanToken.approve(address(curveLiquidityGauge), MAX_UINT256);
        beanToken.approve(address(beanstalk), MAX_UINT256);
        bean3CRVToken.approve(address(beanstalk), MAX_UINT256);
    }

    // --- User-facing functions ---

    // TODO: Create two different bond functions: 
    // 2: CreateBondCrates, that takes in multiple crates (i.e multiple season deposits)
    // - the above will need an array of amounts + an array of crates that match that 
    // - pls no mix and match crates from BEAN/BEAN3CRV

    // creates a bond from bean that is external (not deposited in the silo).
    function createBondExternal(TokenType _token, uint128 _amount) public returns (uint256) {
        _requireMinBond(_amount);
        _requireMigrationNotActive();
        _updateAccrualParameter();

        // Mint the bond NFT to the caller and get the bond ID
        (uint256 bondID, uint80 initialHalfDna) = bondNFT.mint(
            msg.sender, 
            (beanBuckets.permenent + bean3CrvBuckets.permenent) / NFT_RANDOMNESS_DIVISOR
        );
        
        BondData memory bondData;
        bondData.amount = _amount;
        bondData.startTime = uint48(block.timestamp);
        bondData.status = BondStatus.active;
        bondData.season = beanstalk.season();
        bondData.token = token;
        idToBondData[bondID] = bondData;

        totalWeightedStartTimes += _amount * block.timestamp;
        
        // TODO update to transfer BEAN or BEAN3CRV

        // transfer bean to manager, then deposit
        if (_token == TokenType.BEAN) {
            beanBuckets.pendingAmt += _amount;
            beanstalk.transferToken(beanToken, address(this), _amount, EXTERNAL, INTERNAL);
            beanstalk.deposit(address(beanToken), _amount, INTERNAL);
        }

        if (_token == TokenType.BEAN3CRV) {
            bean3CrvBuckets.pendingAmt += _amount;
            beanstalk.transferToken(bean3CRVToken, address(this), _amount, EXTERNAL, INTERNAL);
            beanstalk.deposit(address(bean3CRVToken), _amount, INTERNAL);
        }        

        // TODO: change amount to  BDV 
        emit BondCreated(msg.sender, bondID, _token, _amount, initialHalfDna);

        return bondID;
    }

    // creates a bond from bean that is internal (not deposited in the silo) from 1 season
    function createBondInternal(TokenType _token, uint32 _season, uint128 _amount) public returns (uint256) {
        _requireMinBond(_amount);
        _requireMigrationNotActive();
        _updateAccrualParameter();

        // Mint the bond NFT to the caller and get the bond ID
        (uint256 bondID, uint80 initialHalfDna) = bondNFT.mint(
            msg.sender, 
            (beanBuckets.permenent + bean3CrvBuckets.permenent) / NFT_RANDOMNESS_DIVISOR
        );
        
        BondData memory bondData;
        bondData.Amount = _amount;
        bondData.startTime = uint48(block.timestamp);
        bondData.status = BondStatus.active;
        bondData.season = _season;
        bondData.token = _token;
        idToBondData[bondID] = bondData;

        totalWeightedStartTimes += _amount * block.timestamp;
        
        // TODO update to transfer BEAN or BEAN3CRV

        // transfer bean to bond manager
        if (_token == TokenType.BEAN) {
            beanBuckets.pendingAmt += _amount;
            beanstalk.transferDeposit(address(this), beanToken, _season, _amount);
        }

        if (_token == TokenType.BEAN3CRV) {
            bean3CrvBuckets.pendingAmt += _amount;
            beanstalk.transferDeposit(address(this), bean3CRVToken, _amount);
        }        

        // TODO: change amount to  BDV 
        emit BondCreated(msg.sender, bondID, _token, _amount, initialHalfDna);

        return bondID;
    }

    function createBondInternalCrates(bytes calldata convertData, TokenType _token, uint32[] _crates, uint256[] _amounts) public returns (uint256) {
        // we convert the deposits into one, then call createbondInternal
        (x,y,z,a) = beanstalk.convert(convertData, _crates, _amounts);
        createBondInternal(_token,season,amount);
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
        // LCB-10: don't call permit if the user already has the required amount permitted
        // does beanstalk also do this? 
        if (beanToken.allowance(owner, address(this)) < amount) {
            beanToken.permit(owner, address(this), amount, deadline, v, r, s);
        }
        return createBondExternal(amount);
    }

    function chickenOut(uint256 _bondID, uint256 _minLUSD) external {
        BondData memory bond = idToBondData[_bondID];

        _requireCallerOwnsBond(_bondID);
        _requireActiveStatus(bond.status);

        _updateAccrualParameter();

        idToBondData[_bondID].status = BondStatus.chickenedOut;
        idToBondData[_bondID].endTime = uint64(block.timestamp);

        // TODO: Need to figure out on-chain dynamic NFT traits
        uint80 newDna = bondNFT.setFinalExtraData(msg.sender, _bondID, permanentBEAN / NFT_RANDOMNESS_DIVISOR);

        countChickenOut += 1;

        pendingBEAN -= bond.beanAmount;
        totalWeightedStartTimes -= bond.beanAmount * bond.startTime;

        beanstalk.transferDeposit(address(this),msg.sender,bond.token,bond.season,bond.amount);

        emit BondCancelled(msg.sender, _bondID, bond.beanAmount, newDna);
    }

    // transfer _lusdToTransfer to the LUSD/bLUSD AMM LP Rewards staking contract
    function _transferToRewardsStakingContract(uint256 _lusdToTransfer) internal {
        // TODO: Should we reward both BEAN + BEAN3CRV, or should we sell BEAN3CRV to BEAN and reward 1 
        uint256 lusdBalanceBefore = beanToken.balanceOf(address(this));
        curveLiquidityGauge.deposit_reward_token(address(beanToken), _lusdToTransfer);

        assert(lusdBalanceBefore - beanToken.balanceOf(address(this)) == _lusdToTransfer);
    }

    function _withdrawFromSPVaultAndTransferToRewardsStakingContract(uint256 _beanAmount) internal {
        // Pull the LUSD amount from B.Protocol LUSD vault
        // TODO: Need to call withdraw function, then claim it to bring it out of beanstalk 
        // TODO: Has 1 hour claim time 
        _withdrawFromSilo(_beanAmount, address(this));

        // Deposit in rewards contract
        _transferToRewardsStakingContract(_beanAmount);
    }

    /* Divert acquired yield to LUSD/bLUSD AMM LP rewards staking contract
     * It happens on the very first chicken in event of the system, or any time that redemptions deplete bLUSD total supply to zero
     * Assumption: When there have been no chicken ins since the bLUSD supply was set to 0 (either due to system deployment, or full bLUSD redemption),
     * all acquired LUSD must necessarily be pure yield.
     */
    function _firstChickenIn(uint256 _bondStartTime, uint256 reserveBEAN) internal {
        //assert(!migration); // we leave it as a comment so we can uncomment it for automated testing tools

        require(block.timestamp >= _bondStartTime + BOOTSTRAP_PERIOD_CHICKEN_IN, "CBM: First chicken in must wait until bootstrap period is over");
        firstChickenInTime = block.timestamp;

        // acquired yield comes when you call plant. 
        earnedBeans = beanstalk.plant();

        
        if (earnedBeans > 0) {
            _withdrawFromSPVaultAndTransferToRewardsStakingContract(earnedBeans);
        }

        //return _lusdInBAMMSPVault - acquiredLUSDInSP;
    }


    function chickenIn(uint256 _bondID, bytes calldata convertData) external {
        BondData memory bond = idToBondData[_bondID];

        _requireCallerOwnsBond(_bondID);
        _requireActiveStatus(bond.status);

        uint256 updatedAccrualParameter = _updateAccrualParameter();

        // TODO: What is beanstalk equilivant?
        // we need to get the total beans in the silo 
        // ok cujo told me that there isn't an onchain way to get Farmer Deposited Token Balances, 
        // we have to store + update whenever its added (reserveBEAN)

        //(uint256 bammLUSDValue, uint256 lusdInBAMMSPVault) = _updateBAMMDebt();

        (uint256 chickenInFeeAmount, uint256 bondAmountMinusChickenInFee) = _getBondWithChickenInFeeApplied(bond.beanAmount);

        /* Upon the first chicken-in after a) system deployment or b) redemption of the full bLUSD supply, divert
        * any earned yield to the bLUSD-LUSD AMM for fairness.
        *
        * This is not done in migration mode since there is no need to send rewards to the staking contract.
        */
        /// TODO: Come back to this        
        if (bBEANToken.totalSupply() == 0 && !migration) {
            _firstChickenIn(bond.startTime, bond.token);
        }


        // Get the BEAN amount to acquire from the bond in proportion to the system's current backing ratio, in order to maintain said ratio.
        uint256 beanToAcquire = _calcAccruedAmount(bond.startTime, bondAmountMinusChickenInFee, updatedAccrualParameter);
        // Get backing ratio and accrued bBEAN
        uint256 backingRatio = calcSystemBackingRatio();
        uint256 accruedBBEAN = beanToAcquire * 1e18 / backingRatio;

        idToBondData[_bondID].claimedBBEAN = uint64(Math.min(accruedBBEAN / 1e18, type(uint64).max)); // to units and uint64
        idToBondData[_bondID].status = BondStatus.chickenedIn;
        idToBondData[_bondID].endTime = uint64(block.timestamp);
        uint80 newDna = bondNFT.setFinalExtraData(msg.sender, _bondID, permanentBEAN / NFT_RANDOMNESS_DIVISOR);

        countChickenIn += 1;

        // Subtract the bonded amount from the total pending LUSD (and implicitly increase the total acquired LUSD)
        pendingBEAN -= bond.beanAmount;

        TokenType _token = bond.token;

        // increment reseserve BEAN or BEAN3CRV
        // additionally, we merge the deposit season + the reserve season into 1 season,
        // using the new landa_landa convert
        if(TokenType == BEAN) {
            reserveBEAN += beanToAcquire;
            uint32[2] memory crates = [reserveBeanSeason,bondSeason];
            uint32[2] memory amounts = [reserveBean,bondAmt];
            beanstalk.convert(convertData,crates,amounts);
        } else if (TokenType == BEAN3CRV) {
            reserveBEAN3CRV += beanToAcquire;
            uint32[2] memory crates = [reserveBean3CRVSeason,bondSeason];
            uint32[2] memory amounts = [reserveBean3CRV,bondAmt];
            beanstalk.convert(convertData,crates,amounts);
        }
        
        totalWeightedStartTimes -= bond.beanAmount * bond.startTime;

        // Get the remaining surplus from the LUSD amount to acquire from the bond
        uint256 beanSurplus = bondAmountMinusChickenInFee - beanToAcquire;

        // Handle the surplus LUSD from the chicken-in:
        if (!migration) { 
            // In normal mode, add the surplus to the permanent bucket by increasing the permament tracker. This implicitly decreases the acquired LUSD.
            permanentBEAN += beanSurplus;
        } else { // In migration mode, withdraw surplus from B.Protocol and refund to bonder
            if (beanSurplus > 0) { beanstalk.transferDeposit(address(this),msg.sender,bond.token,bond.season,bond.amount); }
        }

        bBEANToken.mint(msg.sender, accruedBBEAN);

        // Transfer the chicken in fee to the LUSD/bLUSD AMM LP Rewards staking contract during normal mode.
        if (!migration) {
            //_withdrawFromSPVaultAndTransferToRewardsStakingContract(chickenInFeeAmount);
            // TODO: write _queueWithdraw
            _queueWithdraw(chickenInFeeAmount);
            
        }

        // TODO: convert season deposit with the reserve season, 
        emit BondClaimed(msg.sender, _bondID, bond.beanAmount, accruedBBEAN, beanSurplus, chickenInFeeAmount, migration, newDna);
    }

    function redeem(uint256 _bBEANToRedeem, uint256 _minLUSDFromBAMMSPVault) external returns (uint256, uint256) {
        _requireNonZeroAmount(_bBEANToRedeem);
        _requireRedemptionNotDepletingbLUSD(_bBEANToRedeem);

        require(block.timestamp >= firstChickenInTime + BOOTSTRAP_PERIOD_REDEEM, "CBM: Redemption after first chicken in must wait until bootstrap period is over");

        // TODO: not needed as reserve is only held in bean (for now)
        // (
        //     uint256 acquiredLUSDInSP,
        //     uint256 acquiredLUSDInCurve,
        //     /* uint256 ownedLUSDInSP */,
        //     uint256 ownedLUSDInCurve,
        //     uint256 permanentLUSDCached
        // ) = _getLUSDSplit();

        uint256 fractionOfBBEANToRedeem = _bBEANToRedeem * 1e18 / bBEANToken.totalSupply();
        
        // fuck redemption fees, what are we, grifters?
        //uint256 redemptionFeePercentage = migration ? 0 : _updateRedemptionFeePercentage(fractionOfBBEANToRedeem);
        


        _requireNonZeroAmount(reserveBEAN * 1e12 + reserveBEAN3CRV);

        // Burn the redeemed bLUSD
        bBEANToken.burn(msg.sender, _bBEANToRedeem);

        { // Block scoping to avoid stack too deep issues
            // TODO: need to store season in which reserveBEAN + reserveBEAN3CRV is in 
            uint256 reserveBEANToRedeem = reserveBEAN * fractionOfBBEANToRedeem / 1e18;
            uint256 reserveBEAN3CRVToRedeem = reserveBEAN3CRV * fractionOfBBEANToRedeem / 1e18;

            if (reserveBEANToRedeem > 0) beanstalk.transferDeposit(address(this), msg.sender, BEAN, bond.season, bond.amount);
            if (reserveBEAN3CRVToRedeem > 0) beanstalk.transferDeposit(address(this), msg.sender, BEAN3CRV, bond.season, bond.amount);
        }

        emit BBEANRedeemed(msg.sender, _bBEANToRedeem, reserveBEANToRedeem, reserveBEAN3CRVToRedeem);

        return (reserveBEANToRedeem, reserveBEAN3CRVToRedeem);
    }
    

    // TODO: much of this logic can be put on the convert function already made
    // TODO: limit converts at minimum 1.0004, or 0.9996, due to fee.  
    // Open questions: 
    // 1: do we allow reserve Beans / bean3CRV to be converted? -> 
    // 2: do we convert reserves or permenent Beans first? ->
    
    function convert(bytes calldata convertData) external {
        _requireShiftBootstrapPeriodEnded();
        _requireMigrationNotActive();
        _requireNonZeroBBEANSupply();
        _requireShiftWindowIsOpen();

        uint32[] memory crates;
        uint256[] memory amounts;

        // determine whether we're converting BEAN -> BEAN LP, or vice versa
        // we convert 
        LibConvertData.ConvertKind kind = convertData.convertKind();

        if (kind == LibConvertData.ConvertKind.BEANS_TO_CURVE_LP) {
            crates.push()
            amounts.push(reserveBEAN )
        } else if (kind == LibConvertData.ConvertKind.BEANS_TO_CURVE_LP) {
            
        } else {
            revert("Incorrect ConvertData");
        } 


        // We can’t shift more than what’s in Curve
        uint256 _maxBEANLPToShift = Math.min(_maxBEANLPToShift, permanentBEAN3CRV);
        _requireNonZeroAmount(_maxBEANLPToShift);

        // Get the 3CRV virtual price only once, and use it for both initial and final check.
        // Removing LUSD liquidity from the meta-pool does not change 3CRV virtual price.
        uint256 _3crvVirtualPrice = curveBasePool.get_virtual_price();
        uint256 initialExchangeRate = _get3CRVBEANExchangeRate(_3crvVirtualPrice);

        // Here we're using the 3CRV:LUSD exchange rate (with 3CRV being valued at its virtual price),
        // which increases as LUSD price decreases, hence the direction of the inequality.
        require(
            initialExchangeRate > curveWithdrawalBEAN3CRVExchangeRateThreshold,
            "CBM: 3CRV:BEAN exchange rate must be above the withdrawal threshold before Curve->SP shift"
        );
        
        beanstalk.convert(convertData,crates,amounts);
        permanentBEAN -= fromAmount;
        permanentBEAN3CRV += toAmount;
    }

    // plants earned beans
    // we need to add this to the reserve season, but it does take some gas 
    // input is a lamda lamda convert
    // no benefit to the user to call other than adding earned beans to the reserve. 
    function plant(bytes calldata convertData) external {
        // cannot be called if the first chicken in has occured. 
        require(firstChickenInTime != 0);
        uint256 earnedBeans = beanstalk.plant();
        reserveBEAN += earnedBeans;
        current_season = beanstalk.season();
        uint32[2] memory crates = [reserveBeanSeason,current_season];
        uint32[2] memory amounts = [reserveBean,earnedBeans];
        beanstalk.convert(convertData,crates,amounts);
    }

    function _requireAbovePeg() internal view returns (bool) {
        require(Beanstalk.abovePeg() == true);
    }

    function _requireBelowPeg() internal view returns (bool) {
        require(Beanstalk.abovePeg() == false);
    }

    // --- Migration functionality ---

    /* Migration function callable one-time and only by Yearn governance.
    * Moves all permanent LUSD in Curve to the Curve acquired bucket.
    */
    // TODO: think about how we should handle this? maybe transfer permentant to EOA (like bean sprout gnosis)
    function activateMigration() external {
        _requireCallerIsBeanSproutGovernance();
        _requireMigrationNotActive();

        migration = true;

        emit MigrationTriggered(permanentBEAN);

        // Zero the permament LUSD tracker. This implicitly makes all permament liquidity acquired (and redeemable)
        permanentBEAN = 0;
    }

    // --- Shifter countdown starter ---

    function startShifterCountdown() public {
        // First check that the previous delay and shifting window have passed
        require(block.timestamp >= lastShifterCountdownStartTime + SHIFTER_DELAY + SHIFTER_WINDOW, "CBM: Previous shift delay and window must have passed");

        // Begin the new countdown from now
        lastShifterCountdownStartTime = block.timestamp;
    }

    // --- Helper functions ---
    // TODO change 
    function _getBEAN3CRVExchangeRate(uint256 _3crvVirtualPrice) internal view returns (uint256) {
        // Get the amount of 3CRV that would be received by swapping 1 LUSD (after deduction of fees)
        // If p_{LUSD:3CRV} is the price of LUSD quoted in 3CRV, then this returns p_{LUSD:3CRV} * (1 - fee)
        // as long as the pool is large enough so that 1 LUSD doesn't introduce significant slippage.
        uint256 dy = curvePool.get_dy(INDEX_OF_LUSD_TOKEN_IN_CURVE_POOL, INDEX_OF_3CRV_TOKEN_IN_CURVE_POOL, 1e18);

        return dy * _3crvVirtualPrice / 1e18;
    }
    // TODO change 
    function _get3CRVBEANExchangeRate(uint256 _3crvVirtualPrice) internal view returns (uint256) {
        // Get the amount of LUSD that would be received by swapping 1 3CRV (after deduction of fees)
        // If p_{3CRV:LUSD} is the price of 3CRV quoted in LUSD, then this returns p_{3CRV:LUSD} * (1 - fee)
        // as long as the pool is large enough so that 1 3CRV doesn't introduce significant slippage.
        uint256 dy = curvePool.get_dy(INDEX_OF_3CRV_TOKEN_IN_CURVE_POOL, INDEX_OF_LUSD_TOKEN_IN_CURVE_POOL, 1e18);

        return dy * 1e18 / _3crvVirtualPrice;
    }

    // Calc decayed redemption rate
    /// note: no fees, functions not needed
    // function calcRedemptionFeePercentage(uint256 _fractionOfBLUSDToRedeem) public view returns (uint256) {
    //     uint256 minutesPassed = _minutesPassedSinceLastRedemption();
    //     uint256 decayFactor = decPow(MINUTE_DECAY_FACTOR, minutesPassed);

    //     uint256 decayedBaseRedemptionRate = baseRedemptionRate * decayFactor / DECIMAL_PRECISION;

    //     // Increase redemption base rate with the new redeemed amount
    //     uint256 newBaseRedemptionRate = decayedBaseRedemptionRate + _fractionOfBLUSDToRedeem / BETA;
    //     newBaseRedemptionRate = Math.min(newBaseRedemptionRate, DECIMAL_PRECISION); // cap baseRate at a maximum of 100%
    //     //assert(newBaseRedemptionRate <= DECIMAL_PRECISION); // This is already enforced in the line above

    //     return newBaseRedemptionRate;
    // }

    // Update the base redemption rate and the last redemption time (only if time passed >= decay interval. This prevents base rate griefing)
    // function _updateRedemptionFeePercentage(uint256 _fractionOfBLUSDToRedeem) internal returns (uint256) {
    //     uint256 newBaseRedemptionRate = calcRedemptionFeePercentage(_fractionOfBLUSDToRedeem);
    //     baseRedemptionRate = newBaseRedemptionRate;
    //     emit BaseRedemptionRateUpdated(newBaseRedemptionRate);

    //     uint256 timePassed = block.timestamp - lastRedemptionTime;

    //     if (timePassed >= SECONDS_IN_ONE_MINUTE) {
    //         lastRedemptionTime = block.timestamp;
    //         emit LastRedemptionTimeUpdated(block.timestamp);
    //     }

    //     return newBaseRedemptionRate;
    // }

    function _minutesPassedSinceLastRedemption() internal view returns (uint256) {
        return (block.timestamp - lastRedemptionTime) / SECONDS_IN_ONE_MINUTE;
    }

    function _getBondWithChickenInFeeApplied(uint256 _bondBEANAmount) internal view returns (uint256, uint256) {
        // Apply zero fee in migration mode
        if (migration) {return (0, _bondBEANAmount);}

        // Otherwise, apply the constant fee rate
        uint256 chickenInFeeAmount = _bondBEANAmount * CHICKEN_IN_AMM_FEE / 1e18;
        uint256 bondAmountMinusChickenInFee = _bondBEANAmount - chickenInFeeAmount;

        return (chickenInFeeAmount, bondAmountMinusChickenInFee);
    }

    function _getBondAmountMinusChickenInFee(uint256 _bondBEANAmount) internal view returns (uint256) {
        (, uint256 bondAmountMinusChickenInFee) = _getBondWithChickenInFeeApplied(_bondBEANAmount);
        return bondAmountMinusChickenInFee;
    }

    /* _calcAccruedAmount: internal getter for calculating accrued token amount for a given bond.
    *
    * This function is unit-agnostic. It can be used to calculate a bonder's accrrued bLUSD, or the LUSD that that the
    * CB system would acquire (i.e. receive to the acquired bucket) if the bond were Chickened In now.
    *
    * For the bonder, _capAmount is their bLUSD cap.
    * For the CB system, _capAmount is the LUSD bond amount (less the Chicken In fee).
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
            pendingBEAN + pendingBEAN3CRV == 0
        ) {
            return (_storedAccrualParameter, updatedAccrualAdjustmentPeriodCount);
        }

        uint256 averageStartTime = totalWeightedStartTimes / pendingBEAN;

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

    // Internal getter for calculating the bond bLUSD cap based on bonded amount and backing ratio
    function _calcBondBBEANCap(uint256 _bondedAmount, uint256 _backingRatio) internal pure returns (uint256) {
        // TODO: potentially refactor this -  i.e. have a (1 / backingRatio) function for more precision
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
        require(bBEANToken.totalSupply() > 0, "CBM: bLUSD Supply must be > 0 upon shifting");
    }

    function _requireMinBond(uint256 _beanAmount) internal view {
        require(_beanAmount >= MIN_BOND_AMOUNT, "CBM: Bond minimum amount not reached");
    }

    // should we keep this?
    function _requireRedemptionNotDepletingbLUSD(uint256 _bBEANToRedeem) internal view {
        if (!migration) {
            //require(_bBEANToRedeem < bLUSDTotalSupply, "CBM: Cannot redeem total supply");
            require(_bBEANToRedeem + MIN_BBEAN_SUPPLY <= bBEANToken.totalSupply(), "CBM: Cannot redeem below min supply");
        }
    }

    function _requireMigrationNotActive() internal view {
        require(!migration, "CBM: Migration must be not be active");
    }
    // TODO change
    function _requireCallerIsBeanSproutGovernance() internal view {
        require(msg.sender == BeanSproutGovernance, "CBM: Only Yearn Governance can call");
    }

    function _requireShiftBootstrapPeriodEnded() internal view {
        require(block.timestamp - deploymentTimestamp >= BOOTSTRAP_PERIOD_SHIFT, "CBM: Shifter only callable after shift bootstrap period ends");
    }

    function _requireShiftWindowIsOpen() internal view {
        uint256 shiftWindowStartTime = lastShifterCountdownStartTime + SHIFTER_DELAY;
        uint256 shiftWindowFinishTime = shiftWindowStartTime + SHIFTER_WINDOW;

        require(block.timestamp >= shiftWindowStartTime && block.timestamp < shiftWindowFinishTime, "CBM: Shift only possible inside shifting window");
    }

    // --- Getter convenience functions ---

    // Bond getters

    // TODO: Change
    function getBondData(uint256 _bondID)
        external
        view
        returns (
            uint256 beanAmount,
            uint64 claimedBBEAN,
            uint64 startTime,
            uint64 endTime,
            uint8 status
        )
    {
        BondData memory bond = idToBondData[_bondID];
        return (bond.beanAmount, bond.claimedBBEAN, bond.startTime, bond.endTime, uint8(bond.status));
    }

    function getBEANToAcquire(uint256 _bondID) external view returns (uint256) {
        BondData memory bond = idToBondData[_bondID];

        (uint256 updatedAccrualParameter, ) = _calcUpdatedAccrualParameter(accrualParameter, accrualAdjustmentPeriodCount);

        return _calcAccruedAmount(bond.startTime, _getBondAmountMinusChickenInFee(bond.beanAmount), updatedAccrualParameter);
    }

    function calcAccruedBBEAN(uint256 _bondID) external view returns (uint256) {
        BondData memory bond = idToBondData[_bondID];

        if (bond.status != BondStatus.active) {
            return 0;
        }

        uint256 bondBBEANCap = _calcBondBBEANCap(_getBondAmountMinusChickenInFee(bond.beanAmount), calcSystemBackingRatio());

        (uint256 updatedAccrualParameter, ) = _calcUpdatedAccrualParameter(accrualParameter, accrualAdjustmentPeriodCount);

        return _calcAccruedAmount(bond.startTime, bondBBEANCap, updatedAccrualParameter);
    }

    function calcBondBBEANCap(uint256 _bondID) external view returns (uint256) {
        uint256 backingRatio = calcSystemBackingRatio();

        BondData memory bond = idToBondData[_bondID];

        return _calcBondBBEANCap(_getBondAmountMinusChickenInFee(bond.beanAmount), backingRatio);
    }

    function calcSystemBackingRatio() public view returns (uint256) {
        uint256 totalBBEANSupply = bBEANToken.totalSupply();
        //(uint256 acquiredLUSDInSP, uint256 acquiredLUSDInCurve,,,) = _getLUSDSplit(_bammLUSDValue);

        /* TODO: Determine how to define the backing ratio when there is 0 bLUSD and 0 totalAcquiredLUSD,
         * i.e. before the first chickenIn. For now, return a backing ratio of 1. Note: Both quantities would be 0
         * also when the bLUSD supply is fully redeemed.
         */
        if (totalBBEANSupply == 0) {return 1e18;}
        
        // BEAN is 6 decimals, BEAN3CRV is 18 Decimals
        // TODO: can we assume 1 BEAN = 1 BEAN3CRV LP when DeltaB == 0? 
        return  ((reserveBEAN * 1e12) + reserveBEAN3CRV)  / totalBBEANSupply;

    }

    // TODO: read up
    function calcUpdatedAccrualParameter() external view returns (uint256) {
        (uint256 updatedAccrualParameter, ) = _calcUpdatedAccrualParameter(accrualParameter, accrualAdjustmentPeriodCount);
        return updatedAccrualParameter;
    }

    function getOpenBondCount() external view returns (uint256 openBondCount) {
        return bondNFT.totalSupply() - countChickenIn - countChickenOut;
    }

    // Random stuff
    // TODO: Change to wrapper for beanstalk withdraw
    function _withdrawFromSilo(uint256 _beanAmount, address _to) internal {
        beanstalk.withdrawDeposits(address(beanToken), seasons,_beanAmount);
       //bammLUSDDebt -= _beanAmount
    }

    function _claimFromSilo(uint256 _beanAmount, address _to) internal {
        beanstalk.claim(_to,_beanAmount);
    }
}