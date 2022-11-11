// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

import "../Interfaces/IBAMM.sol";
import "../test/TestContracts/LUSDTokenTester.sol";

import "forge-std/console.sol";


contract MockBAMMSPVault is IBAMM {
    LUSDTokenTester public beanToken;
    uint256 lusdValue;

    constructor(address _lusdTokenAddress) {
        beanToken = LUSDTokenTester(_lusdTokenAddress);
    }

    function deposit(uint256 _beanAmount) external {
        lusdValue += _beanAmount;
        beanToken.transferFrom(msg.sender, address(this), _beanAmount);

        return;
    }

    function withdraw (uint256 _beanAmount, address _to) external {
        lusdValue -= _beanAmount;
        beanToken.transfer(_to, _beanAmount);

        return;
    }

    function swap(uint beanAmount, uint minEthReturn, address payable dest) public returns(uint) {}

    function getSwapEthAmount(uint lusdQty) public view returns(uint ethAmount, uint feeLusdAmount) {}

    function getLUSDValue() external view returns (uint256, uint256, uint256) {
        uint256 lusdBalance = beanToken.balanceOf(address(this));
        return (lusdValue, lusdBalance, 0);
    }

    function setChicken(address _chicken) external {}
}
