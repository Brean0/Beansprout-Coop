// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

import "../Interfaces/IChickenBondManager.sol";
import "../Interfaces/ICurvePool.sol";
import "../Interfaces/IYearnVault.sol";
import "openzeppelin-contracts/contracts/utils/Address.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

//import "forge-std/console.sol";


contract ChickenBondOperationsScript {
    IChickenBondManager immutable chickenBondManager;
    IERC20 immutable beanToken;
    IERC20 immutable bBEANToken;
    ICurvePool immutable curvePool;
    IYearnVault immutable public yearnCurveVault;

    int128 immutable INDEX_OF_LUSD_TOKEN_IN_CURVE_POOL;// = 0;

    constructor(IChickenBondManager _chickenBondManager) {
        require(Address.isContract(address(_chickenBondManager)), "ChickenBondManager is not a contract");

        chickenBondManager = _chickenBondManager;
        beanToken = _chickenBondManager.beanToken();
        bBEANToken = _chickenBondManager.bBEANToken();
        curvePool = _chickenBondManager.curvePool();
        yearnCurveVault = _chickenBondManager.yearnCurveVault();

        INDEX_OF_LUSD_TOKEN_IN_CURVE_POOL = _chickenBondManager.INDEX_OF_LUSD_TOKEN_IN_CURVE_POOL();
    }

    function createBond(uint256 _beanAmount) external {
        // Pull LUSD from owner if needed
        uint256 proxyBalance = beanToken.balanceOf(address(this));
        if (proxyBalance < _beanAmount) {
            beanToken.transferFrom(msg.sender, address(this), _beanAmount - proxyBalance);
        }

        // Approve LUSD
        beanToken.approve(address(chickenBondManager), _beanAmount);

        chickenBondManager.createBond(_beanAmount);
    }

    function chickenOut(uint256 _bondID, uint256 _minLUSD) external {
        (uint256 beanAmount,,,,) = chickenBondManager.getBondData(_bondID);
        assert(beanAmount > 0);

        // Chicken out
        chickenBondManager.chickenOut(_bondID, _minLUSD);

        // send LUSD to owner
        beanToken.transfer(msg.sender, beanAmount);
    }

    function chickenIn(uint256 _bondID) external {
        uint256 balanceBefore = bBEANToken.balanceOf(address(this));

        // Chicken in
        chickenBondManager.chickenIn(_bondID);

        uint256 balanceAfter = bBEANToken.balanceOf(address(this));
        assert(balanceAfter > balanceBefore);

        // send bLUSD to owner
        bBEANToken.transfer(msg.sender, balanceAfter - balanceBefore);
    }

    function redeem(uint256 _bLUSDToRedeem, uint256 _minLUSDFromBAMMSPVault) external {
        // pull first bLUSD if needed:
        uint256 proxyBalance = bBEANToken.balanceOf(address(this));
        if (proxyBalance < _bLUSDToRedeem) {
            bBEANToken.transferFrom(msg.sender, address(this), _bLUSDToRedeem - proxyBalance);
        }

        (uint256 lusdFromBAMMSPVault,uint256 yTokensFromCurveVault) = chickenBondManager.redeem(_bLUSDToRedeem, _minLUSDFromBAMMSPVault);

        // Send LUSD to the redeemer
        if (lusdFromBAMMSPVault > 0) {beanToken.transfer(msg.sender, lusdFromBAMMSPVault);}

        // Send yTokens to the redeemer
        if (yTokensFromCurveVault > 0) {yearnCurveVault.transfer(msg.sender, yTokensFromCurveVault);}
    }

    function redeemAndWithdraw(uint256 _bLUSDToRedeem, uint256 _minLUSDFromBAMMSPVault) external {
        // pull first bLUSD if needed:
        uint256 proxyBalance = bBEANToken.balanceOf(address(this));
        if (proxyBalance < _bLUSDToRedeem) {
            bBEANToken.transferFrom(msg.sender, address(this), _bLUSDToRedeem - proxyBalance);
        }

        (uint256 lusdFromBAMMSPVault,uint256 yTokensFromCurveVault) = chickenBondManager.redeem(_bLUSDToRedeem, _minLUSDFromBAMMSPVault);

        // The LUSD deltas from SP/Curve withdrawals are the amounts to send to the redeemer
        uint256 lusdBalanceBefore = beanToken.balanceOf(address(this));
        uint256 LUSD3CRVBalanceBefore = curvePool.balanceOf(address(this));

        // Withdraw obtained yTokens from both vaults
        if (yTokensFromCurveVault > 0) {yearnCurveVault.withdraw(yTokensFromCurveVault);} // obtain LUSD3CRV from Yearn

        uint256 LUSD3CRVBalanceDelta = curvePool.balanceOf(address(this)) - LUSD3CRVBalanceBefore;

        // obtain LUSD from Curve
        if (LUSD3CRVBalanceDelta > 0) {
            curvePool.remove_liquidity_one_coin(LUSD3CRVBalanceDelta, INDEX_OF_LUSD_TOKEN_IN_CURVE_POOL, 0);
        }

        uint256 lusdBalanceDelta = beanToken.balanceOf(address(this)) - lusdBalanceBefore;
        uint256 totalReceivedLUSD = lusdFromBAMMSPVault + lusdBalanceDelta;
        require(totalReceivedLUSD > 0, "Obtained LUSD amount must be > 0");

        // Send the LUSD to the redeemer
        beanToken.transfer(msg.sender, totalReceivedLUSD);
    }
}
