// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
pragma expermental ABIEncoderV2;

import {LibTransfer} from "beanstalk/token/LibTransfer.sol";


interface IBeanstalk {

    /*´:°•.°•.•´.:˚.°.˚•´.°:°•.°•.•´.:˚.°.˚•´.°:°•.°•.•´.:*/
    /*                 BEAN NOT IN SILO                   */
    /*.•°:°.´•˚.°.˚:.´•.•°.•°:´.´•.•°.•°:°.´:•˚°.°.˚:.´•.•*/

    function deposit(
        address token,
        uint256 amount,
        LibTransfer.From mode 
    ) external payable nonReentrant updateSilo;

    /*´:°•.°•.•´.:˚.°.˚•´.°:°•.°•.•´.:˚.°.˚•´.°:°•.°•.•´.:*/
    /*               BEAN THATS ALREADY IN SILO           */
    /*.•°:°.´•˚.°.˚:.´•.•°.•°:´.´•.•°.•°:°.´:•˚°.°.˚:.´•.•*/

    function transferDeposit(
        address sender,
        address recipient,
        address token,
        uint32 season,
        uint256 amount
    ) external payable nonReentrant returns (uint256 bdv);

    function transferDeposits(
        address sender,
        address recipient,
        address token,
        uint32[] calldata seasons,
        uint256[] calldata amounts
    ) external payable nonReentrant returns (uint256[] memory bdvs);


    /*´:°•.°•.•´.:˚.°.˚•´.°:°•.°•.•´.:˚.°.˚•´.°:°•.°•.•´.:*/
    /*                     CONVERTING                     */
    /*.•°:°.´•˚.°.˚:.´•.•°.•°:´.´•.•°.•°:°.´:•˚°.°.˚:.´•.•*/

    function convert(
        bytes convertData,
        uint32[] crates,
        uint256[] amounts
    ) 
        external 
        payable
        nonReentrant
    returns (
        uint32  toSeason, 
        uint256 fromAmount, 
        uint256 toAmount, 
        uint256 fromBdv, 
        uint256 toBdv
    );

    /*´:°•.°•.•´.:˚.°.˚•´.°:°•.°•.•´.:˚.°.˚•´.°:°•.°•.•´.:*/
    /*               USER REDEEMS bBEAN -> BEAN           */
    /*.•°:°.´•˚.°.˚:.´•.•°.•°:´.´•.•°.•°:°.´:•˚°.°.˚:.´•.•*/

    // 2 options: 
    // 1: we transfer deposit to the redeemer, meaning that the user gains grown stalk as well 
    // 2: we call the withdraw function, then claim 

    // in either option, we must record the season and the amount per season
    // withdraws should be LIFO, meaning that the most recent season deposit should be the one withdrawd.

    // after a shower, think 1 is easier from 
    // an implmentation perspective, 
    // ease of use for the user (no need to withdraw + claim)
    // value accrual of the token due to stalk growth 

    // we should optimize such that permenant bucket gets the most stalk 

    // example: someone chickens ins w/1000 BEAN, and they obtain 75% of the max bBEAN. 
    // 750 BEAN will go to the reserve pool. -> 750 + x stalk credited to reserve.
    // 250 BEAN will go to the permenant pool. -> 250 + x stalk credited to permenant.
    // Instead
    // 1000 BEAN goes to reserve pool. -> 1000 + x stalk to reserve.
    // 250 BEAN from reserve pool goes to permenant pool. 250 + y stalk to permenant. 
    // if y > x, we should do the latter. If x > y, we should do the former. 
    // since withdraws are LIFO, this gives more value to the permenant pool, while not harming the user redeemption.
    // (assumption is that a signficant majority of bBEAN will not be redeemed but rather sold on the open market) 

    
    function farm(bytes[] calldata data) external payable;

    function withdrawDeposit(
        address token,
        uint32 season,
        uint256 amount
    ) external payable updateSilo;

    function withdrawDeposits(
        address token,
        uint32[] calldata seasons,
        uint256[] calldata amounts
    ) external payable updateSilo;

    function transferToken(
        IERC20 token, 
        address recipient, 
        uint256 amount, 
        LibTransfer.From fromMode, 
        LibTransfer.To toMode
    ) external payable;


    function totalEarnedBeans() public view returns (uint256);

    function update(address account) external payable;

    function plant() external payable returns (uint25 beans);

    function claimPlenty() external payable;

}