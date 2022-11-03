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

// import "forge-std/console.sol";


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

    // TODO: REMOVE bammLUSDDebt,yTokensHeldByCBM not needed
    uint256 public pendingBEAN;          // Total pending BEAN. Deposited in the silo.
    uint256 public pendingBEAN3CRV;      // Total pending BEAN3CRV. Deposited in the silo.

    uint256 public permanentBEAN;        // Total permanent BEAN owned by the protocol. deposited in the silo as BEAN or BEAN-3CRV
    uint256 public permanentBEAN3CRV;        // Total permanent BEAN owned by the protocol. deposited in the silo as BEAN or BEAN-3CRV

    uint256 public reserveBEAN;          // Total reserve BEAN. Deposited in the silo.
    uint256 public reserveBEAN3CRV;          // Total reserve BEAN. Deposited in the silo.

    uint256 private bammLUSDDebt;         // Amount “owed” by B.Protocol to ChickenBonds, equals deposits - withdrawals + rewards
    uint256 public yTokensHeldByCBM;      // Computed balance of Y-tokens of LUSD-3CRV vault owned by this contract
                                          // (to prevent certain attacks where attacker increases the balance and thus the backing ratio)

    // --- Data structures ---

    // TODO: remove unneeded addresses
    struct ExternalAdresses {
        address bondNFTAddress;
        address lusdTokenAddress;
        address curvePoolAddress;
        address curveBasePoolAddress;
        address bammSPVaultAddress;
        address yearnCurveVaultAddress;
        address yearnRegistryAddress;
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
        uint256 redemptionFeeBeta;              // Parameter by which to divide the redeemed fraction, in order to calculate the new base rate from a redemption
        uint256 redemptionFeeMinuteDecayFactor; // Factor by which redemption fee decays (exponentially) every minute
    }
    // TODO: see above
    // struct OldBondData {
    //     uint256 beanAmount;
    //     uint64 claimedBBEAN; // In BLUSD units without decimals
    //     uint64 startTime;
    //     uint64 endTime; // Timestamp of chicken in/out event
    //     BondStatus status;
    //     uint32 season;
    //     TokenType token;
    // }
    

    // packed into one slot provides signficiant gas savings for the user
    struct BondData {
        uint128 beanAmount; // lets be honest, the supply of bean won't pass uint128, much less one bond
        uint48 claimedBBEAN; // without decimals, this only overflows if one bond has 100 TRILLION bBEAN
        uint48 startTime; // uint48 is more than big enough to store
        uint48 endTime; // same as above
        uint32 season;
        BondStatus status; // uint8
        TokenType token; // uint8
    }
    
    enum TokenType {
        BEAN,
        BEAN3CRV
    }

    uint256 public firstChickenInTime; // Timestamp of the first chicken in after bLUSD supply is zero
    uint256 public totalWeightedStartTimes; // Sum of `beanAmount * startTime` for all outstanding bonds (used to tell weighted average bond age)
    uint256 public lastRedemptionTime; // The timestamp of the latest redemption
    uint256 public baseRedemptionRate; // The latest base redemption rate
    mapping (uint256 => BondData) private idToBondData;

    /* migration: flag which determines whether the system is in migration mode.

    When migration mode has been triggered:

    - No funds are held in the permanent bucket. Liquidity is either pending, or acquired
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

    uint256 public immutable MIN_BLUSD_SUPPLY;            // Minimum amount of bLUSD supply that must remain after a redemption
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
    event BBEANRedeemed(address indexed redeemer, uint256 bLusdAmount, uint256 minLusdAmount, uint256 beanAmount, uint256 yTokens, uint256 redemptionFee);
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
        beanToken = IBEANToken(_externalContractAddresses.lusdTokenAddress);
        bBEANToken = IBBEANToken(_externalContractAddresses.bLUSDTokenAddress);
        curvePool = ICurvePool(_externalContractAddresses.curvePoolAddress);
        curveBasePool = ICurvePool(_externalContractAddresses.curveBasePoolAddress);
        bammSPVault = IBAMM(_externalContractAddresses.bammSPVaultAddress); // not needed
        yearnCurveVault = IYearnVault(_externalContractAddresses.yearnCurveVaultAddress); // not needed
        yearnRegistry = IYearnRegistry(_externalContractAddresses.yearnRegistryAddress); // not needed
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
        MIN_BLUSD_SUPPLY = _params.minBLUSDSupply;
        require(_params.minBondAmount > 0, "CBM: MIN BOND AMOUNT parameter cannot be zero"); // We can still use 1e-18
        MIN_BOND_AMOUNT = _params.minBondAmount;
        NFT_RANDOMNESS_DIVISOR = _params.nftRandomnessDivisor;
        BETA = _params.redemptionFeeBeta;
        MINUTE_DECAY_FACTOR = _params.redemptionFeeMinuteDecayFactor;

        // TODO: Decide between one-time infinite LUSD approval to Yearn and Curve (lower gas cost per user tx, less secure
        // or limited approval at each bonder action (higher gas cost per user tx, more secure)
        //beanToken.approve(address(bammSPVault), MAX_UINT256); // not needed
        beanToken.approve(address(curvePool), MAX_UINT256); 
        //curvePool.approve(address(yearnCurveVault), MAX_UINT256); // not needed, replace with beanstalk
        beanToken.approve(address(curveLiquidityGauge), MAX_UINT256);
        beanToken.approve(address(beanstalk), MAX_UINT256);
        bean3CRVToken.approve(address(beanstalk), MAX_UINT256);


        // Check that the system is hooked up to the correct latest Yearn vault
        assert(address(yearnCurveVault) == yearnRegistry.latestVault(address(curvePool))); // not needed, replace with beanstalk
    }

    // --- User-facing functions ---

    // TODO: Create two different bond functions: 
    // 1: CreateBond from a single season (i.e 1 deposit is in 1 season). If the bean is external, then season is the current
    // 2: CreateBondCrates, that takes in multiple crates (i.e multiple season deposits)
    // - the above will need an array of amounts + an array of crates that match that 
    // - pls no mix and match crates from BEAN/BEAN3CRV
    function createBondExternal(TokenType token, uint256 _beanAmount) public returns (uint256) {
        // TODO: Allow user to deposit BEAN or BEAN3CRV
        _requireMinBond(_beanAmount);
        _requireMigrationNotActive();

        _updateAccrualParameter();

        // Mint the bond NFT to the caller and get the bond ID
        (uint256 bondID, uint80 initialHalfDna) = bondNFT.mint(msg.sender, permanentBEAN / NFT_RANDOMNESS_DIVISOR);

        //Record the user’s bond data: bond_amount and start_time
        // TODO: need to add an array of crates that the user can deposit in 
        // TODO: _beanAmount will also need to be an array if there are multiple crates
        
        BondData memory bondData;
        bondData.beanAmount = _beanAmount;
        bondData.startTime = uint64(block.timestamp);
        bondData.status = BondStatus.active;
        bondData.season = beanstalk.season();
        bondData.token = token;
        idToBondData[bondID] = bondData;

        if (token == BEAN) pendingBEAN += _beanAmount;
        if (token == BEAN3CRV) pendingBEAN3CRV += _beanAmount;

        totalWeightedStartTimes += _beanAmount * block.timestamp;
        
        // TODO update to transfer BEAN or BEAN3CRV

        // transfer bean to manager, then deposit
        if (token == BEAN) {
            beanstalk.transferToken(beanToken, address(this), _beanAmount, EXTERNAL, INTERNAL);
            beanstalk.deposit(address(beanToken), _beanAmount, INTERNAL);
        }

        if (token == BEAN3CRV) {
            beanstalk.transferToken(bean3CRVToken, address(this), _beanAmount, EXTERNAL, INTERNAL);
            beanstalk.deposit(address(bean3CRVToken), _beanAmount, INTERNAL);
        }        

        // Deposit the LUSD to the B.Protocol LUSD vault
        // _depositToBAMM(_beanAmount);
        // TODO: change _beanAmount to  BDV 
        emit BondCreated(msg.sender, bondID, token, _beanAmount, initialHalfDna);

        return bondID;
    }

    function createBondInternal(TokenType token, uint256 _beanAmount) public returns (uint256) {
    }

    function createBondInternalCrates(TokenType token, uint256 _beanAmount) public returns (uint256) {
    }

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
    function _firstChickenIn(uint256 _bondStartTime, uint256 _bammLUSDValue, uint256 _lusdInBAMMSPVault) internal returns (uint256) {
        //assert(!migration); // we leave it as a comment so we can uncomment it for automated testing tools

        require(block.timestamp >= _bondStartTime + BOOTSTRAP_PERIOD_CHICKEN_IN, "CBM: First chicken in must wait until bootstrap period is over");
        firstChickenInTime = block.timestamp;

        // TODO: Replace with _getEarnedBeans instead for beanstalk 
        (
            uint256 acquiredLUSDInSP,
            /* uint256 acquiredLUSDInCurve */,
            /* uint256 ownedLUSDInSP */,
            /* uint256 ownedLUSDInCurve */,
            /* uint256 permanentLUSDCached */
        ) = _getLUSDSplit(_bammLUSDValue); 

        // Make sure that LUSD available in B.Protocol is at least as much as acquired
        // If first chicken in happens after an scenario of heavy liquidations and before ETH has been sold by B.Protocol
        // so that there’s not enough LUSD available in B.Protocol to transfer all the acquired bucket to the staking contract,
        // the system would start with a backing ratio greater than 1
        // TODO: This case will not occur 
        require(_lusdInBAMMSPVault >= acquiredLUSDInSP, "CBM: Not enough LUSD available in B.Protocol");

        // From SP Vault
        if (acquiredLUSDInSP > 0) {
            _withdrawFromSPVaultAndTransferToRewardsStakingContract(acquiredLUSDInSP);
        }

        return _lusdInBAMMSPVault - acquiredLUSDInSP;
    }

    function chickenIn(uint256 _bondID) external {
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
            lusdInBAMMSPVault = _firstChickenIn(bond.startTime, bammLUSDValue, lusdInBAMMSPVault);
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

        if(TokenType == BEAN) {
            reserveBEAN += beanToAcquire;
        } else if (TokenType == BEAN3CRV) {
            reserveBEAN3CRV += beanToAcquire;
        }
        
        totalWeightedStartTimes -= bond.beanAmount * bond.startTime;

        // Get the remaining surplus from the LUSD amount to acquire from the bond
        uint256 beanSurplus = bondAmountMinusChickenInFee - beanToAcquire;

        // Handle the surplus LUSD from the chicken-in:
        if (!migration) { // In normal mode, add the surplus to the permanent bucket by increasing the permament tracker. This implicitly decreases the acquired LUSD.
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
        (
            uint256 acquiredLUSDInSP,
            uint256 acquiredLUSDInCurve,
            /* uint256 ownedLUSDInSP */,
            uint256 ownedLUSDInCurve,
            uint256 permanentLUSDCached
        ) = _getLUSDSplit();

        uint256 fractionOfBBEANToRedeem = _bBEANToRedeem * 1e18 / bBEANToken.totalSupply();
        
        // fuck redemption fees, what are we, grifters?
        //uint256 redemptionFeePercentage = migration ? 0 : _updateRedemptionFeePercentage(fractionOfBBEANToRedeem);
        


        _requireNonZeroAmount(lusdToWithdrawFromSP + yTokensFromCurveVault);

        // Burn the redeemed bLUSD
        bBEANToken.burn(msg.sender, _bBEANToRedeem);

        { // Block scoping to avoid stack too deep issues
            // TODO: need to store season in which reserveBEAN + reserveBEAN3CRV is in 
            uint256 reserveBEANToRedeem = reserveBEAN * fractionOfBBEANToRedeem / 1e18;
            uint256 reserveBEAN3CRVToRedeem = reserveBEAN3CRV * fractionOfBBEANToRedeem / 1e18;

            if (reserveBEANToRedeem > 0) beanstalk.transferDeposit(address(this), msg.sender, BEAN, bond.season, bond.amount);
            if (reserveBEAN3CRVToRedeem > 0) beanstalk.transferDeposit(address(this), msg.sender, BEAN3CRV, bond.season, bond.amount);
        }

        emit BBEANRedeemed(msg.sender, _bBEANToRedeem, _minLUSDFromBAMMSPVault, lusdToWithdrawFromSP, yTokensFromCurveVault, redemptionFeeLUSD);

        return (lusdToWithdrawFromSP, yTokensFromCurveVault);
    }
    

    // TODO: much of this logic can be put on the convert function already made
    // TODO: limit converts at minimum 1.0004, or 0.9996, due to fee.  
    function convertPermBEANtoLP(uint256 _maxBEANToShift) external {
        _requireShiftBootstrapPeriodEnded();
        _requireMigrationNotActive();
        _requireNonZeroBLUSDSupply();
        _requireShiftWindowIsOpen();

        // TODO: Not needed for beanstalk I believe
        // (uint256 bammLUSDValue, uint256 lusdInBAMMSPVault) = _updateBAMMDebt();
        // uint256 lusdOwnedInBAMMSPVault = bammLUSDValue - pendingBEAN;

        // uint256 totalLUSDInCurve = getTotalLUSDInCurve();
        // it can happen due to profits from shifts or rounding errors:
        // TODO: do we need?
        //_requirePermanentGreaterThanCurve(permanentBEAN);

        // Make sure pending bucket is not moved to Curve, so it can be withdrawn on chicken out
        // TODO: for beanstalk, pending bucket can be moved to bean3CRV, as we redeem via BDV rather than amt
        
        uint256 clampedBEANToShift = Math.min(_maxBEANToShift, permanentBEAN);

        // Make sure there’s enough LUSD available in B.Protocol
        // TODO: not needed
        //clampedBEANToShift = Math.min(clampedBEANToShift, lusdInBAMMSPVault);

        // Make sure we don’t make Curve bucket greater than Permanent one with the shift
        // subtraction is safe per _requirePermanentGreaterThanCurve above
        //clampedBEANToShift = Math.min(clampedBEANToShift, permanentBEAN - totalLUSDInCurve);

        _requireNonZeroAmount(clampedBEANToShift);

        // Get the 3CRV virtual price only once, and use it for both initial and final check.
        // Adding LUSD liquidity to the meta-pool does not change 3CRV virtual price.
        uint256 _3crvVirtualPrice = curveBasePool.get_virtual_price();
        uint256 initialExchangeRate = _getBEAN3CRVExchangeRate(_3crvVirtualPrice);
        
        require(
            initialExchangeRate > curveDepositBEAN3CRVExchangeRateThreshold,
            "CBM: BEAN:3CRV exchange rate must be over the deposit threshold before SP->Curve shift"
        );

        // Withdram LUSD from B.Protocol
        // withdraw not needed, just need to call convert 
        // _withdrawFromSilo(clampedBEANToShift, address(this));

        // Deposit the received LUSD to Curve in return for LUSD3CRV-f tokens
        //uint256 lusd3CRVBalanceBefore = curvePool.balanceOf(address(this));
        /* TODO: Determine if we should pass a minimum amount of LP tokens to receive here. Seems infeasible to determinine the mininum on-chain from
        * Curve spot price / quantities, which are manipulable. */
        //curvePool.add_liquidity([clampedBEANToShift, 0], 0);
        //uint256 lusd3CRVBalanceDelta = curvePool.balanceOf(address(this)) - lusd3CRVBalanceBefore;

        // Deposit the received LUSD3CRV-f to Yearn Curve vault
        // TODO: not needed 
        //_depositToCurve(lusd3CRVBalanceDelta);

        // Do price check: ensure the SP->Curve shift has decreased the LUSD:3CRV exchange rate, but not into unprofitable territory
        // beanstalk does this for us
        //uint256 finalExchangeRate = _getBEAN3CRVExchangeRate(_3crvVirtualPrice);
        permanentBEAN -= fromAmount;
        permanentBEAN3CRV += toAmount;
        // beanstalk handles many errors, such as: 
        // 1 - conversion would cause beanstalk to go under peg
        
        // TODO: Fix psuedocode
        (toSeason,fromAmount,toAmount,fromBdv,toBdv) = beanstalk.convert(convertData,crates,amounts);
        
    }
    // TODO: same comments as above
    // convert is allowed when beanstalk is above peg
    function convertPermLPtoBEAN(uint256 _maxBEANLPToShift) external {
        _requireShiftBootstrapPeriodEnded();
        _requireMigrationNotActive();
        _requireNonZeroBLUSDSupply();
        _requireShiftWindowIsOpen();

        // We can’t shift more than what’s in Curve
        // uint256 ownedLUSDInCurve = getTotalLUSDInCurve();
        uint256 clampedBEANToShift = Math.min(_maxBEANLPToShift, permanentBEAN3CRV);
        _requireNonZeroAmount(clampedBEANToShift);

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

        // Convert yTokens to LUSD3CRV-f
       // uint256 lusd3CRVBalanceBefore = curvePool.balanceOf(address(this));

        // ownedLUSDInCurve > 0 implied by _requireNonZeroAmount(clampedBEANToShift)
        //uint256 yTokensToBurnFromCurveVault = yTokensHeldByCBM * clampedBEANToShift / ownedLUSDInCurve;
        //_withdrawFromCurve(yTokensToBurnFromCurveVault);
        //uint256 lusd3CRVBalanceDelta = curvePool.balanceOf(address(this)) - lusd3CRVBalanceBefore;

        // Withdraw LUSD from Curve
        //uint256 lusdBalanceBefore = beanToken.balanceOf(address(this));
        /* TODO: Determine if we should pass a minimum amount of LUSD to receive here. Seems infeasible to determinine the mininum on-chain from
        * Curve spot price / quantities, which are manipulable. */
        //curvePool.remove_liquidity_one_coin(lusd3CRVBalanceDelta, INDEX_OF_LUSD_TOKEN_IN_CURVE_POOL, 0);
        //uint256 lusdBalanceDelta = beanToken.balanceOf(address(this)) - lusdBalanceBefore;

        // Assertion should hold in principle. In practice, there is usually minor rounding error
        // assert(lusdBalanceDelta == _lusdToShift);

        // Deposit the received LUSD to B.Protocol LUSD vault
        //_depositToBAMM(lusdBalanceDelta);
         // TODO: Fix psuedocode
        (toSeason,fromAmount,toAmount,fromBdv,toBdv) = beanstalk.convert(convertData,crates,amounts);

        // // Ensure the Curve->SP shift has decreased the 3CRV:LUSD exchange rate, but not into unprofitable territory
        // uint256 finalExchangeRate = _get3CRVBEANExchangeRate(_3crvVirtualPrice);

        // require(
        //     finalExchangeRate < initialExchangeRate &&
        //     finalExchangeRate >= curveWithdrawalBEAN3CRVExchangeRateThreshold,
        //     "CBM: Curve->SP shift must increase 3CRV:LUSD exchange rate to a value above the withdrawal threshold"
        // );
    }

    function _requireAbovePeg() internal view returns (bool) {
        require(Beanstalk.abovePeg() == true);
    }

    function _requireBelowPeg() internal view returns (bool) {
        require(Beanstalk.abovePeg() == false);
    }
    // --- B.Protocol debt functions ---

    // If the actual balance of B.Protocol is higher than our internal accounting,
    // it means that B.Protocol has had gains (through sell of ETH or LQTY).
    // We account for those gains
    // If the balance was lower (which would mean losses), we expect them to be eventually recovered
    // TODO: Balance will not change for beanstalk and therefore not needed
    function _getInternalBAMMLUSDValue() internal view returns (uint256) {
        (, uint256 lusdInBAMMSPVault,) = bammSPVault.getLUSDValue();

        return Math.max(bammLUSDDebt, lusdInBAMMSPVault);
    }

    // TODO: Should we make this one publicly callable, so that external getters can be up to date (by previously calling this)?
    // Returns the value updated

    // TODO: Balance will not change for beanstalk and therefore not needed
    // function _updateBAMMDebt() internal returns (uint256, uint256) {
    //     (, uint256 lusdInBAMMSPVault,) = bammSPVault.getLUSDValue();
    //     uint256 bammLUSDDebtCached = bammLUSDDebt;

    //     // If the actual balance of B.Protocol is higher than our internal accounting,
    //     // it means that B.Protocol has had gains (through sell of ETH or LQTY).
    //     // We account for those gains
    //     // If the balance was lower (which would mean losses), we expect them to be eventually recovered
    //     if (lusdInBAMMSPVault > bammLUSDDebtCached) {
    //         bammLUSDDebt = lusdInBAMMSPVault;
    //         return (lusdInBAMMSPVault, lusdInBAMMSPVault);
    //     }

    //     return (bammLUSDDebtCached, lusdInBAMMSPVault);
    // }

    // TODO: Change to wrapper for beanstalk deposit
    // function _depositToBAMM(uint256 _beanAmount) internal {
    //     bammSPVault.deposit(_beanAmount);
    //     bammLUSDDebt += _beanAmount;
    // }

    // TODO: Change to wrapper for beanstalk withdraw
    function _withdrawFromSilo(uint256 _beanAmount, address _to) internal {
        beanstalk.withdrawDeposits(address(beanToken), seasons,_beanAmount);
       //bammLUSDDebt -= _beanAmount
    }

    function _claimFromSilo(uint256 _beanAmount, address _to) internal {
        beanstalk.claim(_to,_beanAmount);
    }

    // @dev make sure this wrappers are always used instead of calling yearnCurveVault functions directyl,
    // otherwise the internal accounting would fail

    // TODO: Change to wrapper for beanstalk deposit
    // function _depositToCurve(uint256 _lusd3CRV) internal {
    //     uint256 yTokensBalanceBefore = yearnCurveVault.balanceOf(address(this));
    //     yearnCurveVault.deposit(_lusd3CRV);
    //     uint256 yTokensBalanceDelta = yearnCurveVault.balanceOf(address(this)) - yTokensBalanceBefore;
    //     yTokensHeldByCBM += yTokensBalanceDelta;
    // }

    // TODO: Change to wrapper for beanstalk withdraw
    // function _withdrawFromCurve(uint256 _yTokensToSwap) internal {
    //     yearnCurveVault.withdraw(_yTokensToSwap);
    //     yTokensHeldByCBM -= _yTokensToSwap;
    // }

    // function _transferFromCurve(address _to, uint256 _yTokensToTransfer) internal {
    //     yearnCurveVault.transfer(_to, _yTokensToTransfer);
    //     yTokensHeldByCBM -= _yTokensToTransfer;
    // }

    // --- Migration functionality ---

    /* Migration function callable one-time and only by Yearn governance.
    * Moves all permanent LUSD in Curve to the Curve acquired bucket.
    */
    // TODO: think about how we should handle this? maybe transfer permentant to EOA (like bean sprout gnosis)
    function activateMigration() external {
        _requireCallerIsYearnGovernance();
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

    // --- Fee share ---
    function sendFeeShare(uint256 _beanAmount) external {
        _requireCallerIsYearnGovernance();
        require(!migration, "CBM: Receive fee share only in normal mode");

        // Move LUSD from caller to CBM and deposit to B.Protocol LUSD Vault
        beanToken.transferFrom(BeanstalkFarmsMultisig, address(this), _beanAmount);
        // TODO change 
        _depositToBAMM(_beanAmount);
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

    // function _minutesPassedSinceLastRedemption() internal view returns (uint256) {
    //     return (block.timestamp - lastRedemptionTime) / SECONDS_IN_ONE_MINUTE;
    // }

    function _getBondWithChickenInFeeApplied(uint256 _bondLUSDAmount) internal view returns (uint256, uint256) {
        // Apply zero fee in migration mode
        if (migration) {return (0, _bondLUSDAmount);}

        // Otherwise, apply the constant fee rate
        uint256 chickenInFeeAmount = _bondLUSDAmount * CHICKEN_IN_AMM_FEE / 1e18;
        uint256 bondAmountMinusChickenInFee = _bondLUSDAmount - chickenInFeeAmount;

        return (chickenInFeeAmount, bondAmountMinusChickenInFee);
    }

    function _getBondAmountMinusChickenInFee(uint256 _bondLUSDAmount) internal view returns (uint256) {
        (, uint256 bondAmountMinusChickenInFee) = _getBondWithChickenInFeeApplied(_bondLUSDAmount);
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
            pendingBEAN == 0
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
    // TODO change 
    function _calcBondBLUSDCap(uint256 _bondedAmount, uint256 _backingRatio) internal pure returns (uint256) {
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
    // TODO change
    function _requireNonZeroBLUSDSupply() internal view {
        require(bBEANToken.totalSupply() > 0, "CBM: bLUSD Supply must be > 0 upon shifting");
    }

    function _requireMinBond(uint256 _beanAmount) internal view {
        require(_beanAmount >= MIN_BOND_AMOUNT, "CBM: Bond minimum amount not reached");
    }

    function _requireRedemptionNotDepletingbLUSD(uint256 _bLUSDToRedeem) internal view {
        if (!migration) {
            //require(_bLUSDToRedeem < bLUSDTotalSupply, "CBM: Cannot redeem total supply");
            require(_bLUSDToRedeem + MIN_BLUSD_SUPPLY <= bBEANToken.totalSupply(), "CBM: Cannot redeem below min supply");
        }
    }

    function _requireMigrationNotActive() internal view {
        require(!migration, "CBM: Migration must be not be active");
    }
    // TODO change
    function _requireCallerIsYearnGovernance() internal view {
        require(msg.sender == BeanstalkFarmsMultisig, "CBM: Only Yearn Governance can call");
    }
    // TODO change
    function _requireEnoughLUSDInBAMM(uint256 _requestedLUSD, uint256 _minLUSD) internal view returns (uint256) {
        require(_requestedLUSD >= _minLUSD, "CBM: Min value cannot be greater than nominal amount");

        (, uint256 lusdInBAMMSPVault,) = bammSPVault.getLUSDValue();
        require(lusdInBAMMSPVault >= _minLUSD, "CBM: Not enough LUSD available in B.Protocol");

        uint256 lusdToWithdraw = Math.min(_requestedLUSD, lusdInBAMMSPVault);

        return lusdToWithdraw;
    }

    function _requireShiftBootstrapPeriodEnded() internal view {
        require(block.timestamp - deploymentTimestamp >= BOOTSTRAP_PERIOD_SHIFT, "CBM: Shifter only callable after shift bootstrap period ends");
    }

    function _requireShiftWindowIsOpen() internal view {
        uint256 shiftWindowStartTime = lastShifterCountdownStartTime + SHIFTER_DELAY;
        uint256 shiftWindowFinishTime = shiftWindowStartTime + SHIFTER_WINDOW;

        require(block.timestamp >= shiftWindowStartTime && block.timestamp < shiftWindowFinishTime, "CBM: Shift only possible inside shifting window");
    }
    // TODO change?
    function _requirePermanentGreaterThanCurve(uint256 _totalBEANInCurve) internal view {
        require(permanentBEAN3CRV >= _totalBEANInCurve, "CBM: The amount in Curve cannot be greater than the Permanent bucket");
    }

    // --- Getter convenience functions ---

    // Bond getters

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
    // TODO change
    function getLUSDToAcquire(uint256 _bondID) external view returns (uint256) {
        BondData memory bond = idToBondData[_bondID];

        (uint256 updatedAccrualParameter, ) = _calcUpdatedAccrualParameter(accrualParameter, accrualAdjustmentPeriodCount);

        return _calcAccruedAmount(bond.startTime, _getBondAmountMinusChickenInFee(bond.beanAmount), updatedAccrualParameter);
    }
    // TODO change
    function calcAccruedBLUSD(uint256 _bondID) external view returns (uint256) {
        BondData memory bond = idToBondData[_bondID];

        if (bond.status != BondStatus.active) {
            return 0;
        }

        uint256 bondBLUSDCap = _calcBondBLUSDCap(_getBondAmountMinusChickenInFee(bond.beanAmount), calcSystemBackingRatio());

        (uint256 updatedAccrualParameter, ) = _calcUpdatedAccrualParameter(accrualParameter, accrualAdjustmentPeriodCount);

        return _calcAccruedAmount(bond.startTime, bondBLUSDCap, updatedAccrualParameter);
    }
    // TODO change
    function calcBondBLUSDCap(uint256 _bondID) external view returns (uint256) {
        uint256 backingRatio = calcSystemBackingRatio();

        BondData memory bond = idToBondData[_bondID];

        return _calcBondBLUSDCap(_getBondAmountMinusChickenInFee(bond.beanAmount), backingRatio);
    }
    // TODO change
    // function getLUSDInBAMMSPVault() external view returns (uint256) {
    //     (, uint256 lusdInBAMMSPVault,) = bammSPVault.getLUSDValue();

    //     return lusdInBAMMSPVault;
    // }
    

    // Native vault token value getters
    // TODO change
    // Calculates the LUSD3CRV value of LUSD Curve Vault yTokens held by the ChickenBondManager
    function calcTotalYearnCurveVaultShareValue() public view returns (uint256) {
        return yTokensHeldByCBM * yearnCurveVault.pricePerShare() / 1e18;
    }
    // TODO change
    // Calculates the LUSD value of this contract, including B.Protocol LUSD Vault and Curve Vault
    function calcTotalLUSDValue() external view returns (uint256) {
        uint256 totalLUSDInCurve = getTotalLUSDInCurve();
        uint256 bammLUSDValue = _getInternalBAMMLUSDValue();

        return bammLUSDValue + totalLUSDInCurve;
    }
    // TODO change
    function getTotalLUSDInCurve() public view returns (uint256) {
        uint256 LUSD3CRVInCurve = calcTotalYearnCurveVaultShareValue();
        uint256 totalLUSDInCurve;
        if (LUSD3CRVInCurve > 0) {
            uint256 LUSD3CRVVirtualPrice = curvePool.get_virtual_price();
            totalLUSDInCurve = LUSD3CRVInCurve * LUSD3CRVVirtualPrice / 1e18;
        }

        return totalLUSDInCurve;
    }

    // Pending getter
    // TODO change
    function getPendingLUSD() external view returns (uint256) {
        return pendingBEAN;
    }

    // Acquired getters
    // TODO change
    // not sure if this is needed, 
    function _getLUSDSplit(uint256 _bammLUSDValue)
        internal
        view
        returns (
            uint256 acquiredLUSDInSP, // reserve BEAN in silo
            uint256 acquiredLUSDInCurve, // reserve BEAN-3CRV in silo
            uint256 ownedLUSDInSP, // permanent BEAN in silo
            uint256 ownedLUSDInCurve, // permanent BEAN3CRV in silo 
            uint256 permanentLUSDCached
        )
    {
        // _bammLUSDValue is guaranteed to be at least pendingBEAN due to the way we track BAMM debt

        ownedLUSDInSP = _bammLUSDValue - pendingBEAN;
        ownedLUSDInCurve = getTotalLUSDInCurve(); // All LUSD in Curve is owned
        permanentLUSDCached = permanentBEAN;

        uint256 ownedLUSD = ownedLUSDInSP + ownedLUSDInCurve;

        if (ownedLUSD > permanentLUSDCached) {
            // ownedLUSD > 0 implied
            uint256 acquiredLUSD = ownedLUSD - permanentLUSDCached;
            acquiredLUSDInSP = acquiredLUSD * ownedLUSDInSP / ownedLUSD;
            acquiredLUSDInCurve = acquiredLUSD - acquiredLUSDInSP;
        }
    }
    // TODO unneeded 
    // Helper to avoid stack too deep in redeem() (we save one local variable)
    // function _getLUSDSplitAfterUpdatingBAMMDebt()
    //     internal
    //     returns (
    //         uint256 acquiredLUSDInSP,
    //         uint256 acquiredLUSDInCurve,
    //         uint256 ownedLUSDInSP,
    //         uint256 ownedLUSDInCurve,
    //         uint256 permanentLUSDCached
    //     )
    // {
    //     (uint256 bammLUSDValue,) = _updateBAMMDebt();
    //     return _getLUSDSplit(bammLUSDValue);
    // }
    // TODO change
    function getTotalAcquiredLUSD() public view returns (uint256) {
        uint256 bammLUSDValue = _getInternalBAMMLUSDValue();
        (uint256 acquiredLUSDInSP, uint256 acquiredLUSDInCurve,,,) = _getLUSDSplit(bammLUSDValue);
        return acquiredLUSDInSP + acquiredLUSDInCurve;
    }
    // TODO change
    function getAcquiredLUSDInSP() external view returns (uint256) {
        uint256 bammLUSDValue = _getInternalBAMMLUSDValue();
        (uint256 acquiredLUSDInSP,,,,) = _getLUSDSplit(bammLUSDValue);
        return acquiredLUSDInSP;
    }
    // TODO change
    function getAcquiredLUSDInCurve() external view returns (uint256) {
        uint256 bammLUSDValue = _getInternalBAMMLUSDValue();
        (, uint256 acquiredLUSDInCurve,,,) = _getLUSDSplit(bammLUSDValue);
        return acquiredLUSDInCurve;
    }

    // note: not needed due to changing vars to public
    // // Permanent getter
    // // TODO change
    // function getPermanentLUSD() external view returns (uint256) {
    //     return permanentBEAN;
    // }

    // // Owned getters
    // // TODO change
    // function getOwnedLUSDInSP() external view returns (uint256) {
    //     uint256 bammLUSDValue = _getInternalBAMMLUSDValue();
    //     (,, uint256 ownedLUSDInSP,,) = _getLUSDSplit(bammLUSDValue);
    //     return ownedLUSDInSP;
    // }
    // // TODO change
    // function getOwnedLUSDInCurve() external view returns (uint256) {
    //     uint256 bammLUSDValue = _getInternalBAMMLUSDValue();
    //     (,,, uint256 ownedLUSDInCurve,) = _getLUSDSplit(bammLUSDValue);
    //     return ownedLUSDInCurve;
    // }

    // Other getters

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


    function calcUpdatedAccrualParameter() external view returns (uint256) {
        (uint256 updatedAccrualParameter, ) = _calcUpdatedAccrualParameter(accrualParameter, accrualAdjustmentPeriodCount);
        return updatedAccrualParameter;
    }
    // TODO change
    // function getBAMMLUSDDebt() external view returns (uint256) {
    //     return bammLUSDDebt;
    // }

    // note: not needed as vars are now public
    // function getTreasury()
    //     external
    //     view
    //     returns (
    //         // We don't normally use leading underscores for return values,
    //         // but we do so here in order to avoid shadowing state variables
    //         uint256 _pendingLUSD,
    //         uint256 _totalAcquiredLUSD,
    //         uint256 _permanentLUSD
    //     )
    // {
    //     _pendingLUSD = pendingBEAN;
    //     _totalAcquiredLUSD = getTotalAcquiredLUSD();
    //     _permanentLUSD = permanentBEAN;
    // }

    function getOpenBondCount() external view returns (uint256 openBondCount) {
        return bondNFT.totalSupply() - countChickenIn - countChickenOut;
    }
}
