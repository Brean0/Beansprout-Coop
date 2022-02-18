
// SPDX-License-Identifier: UNLICENSED

import "../../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

pragma solidity 0.8.10;

interface IMockYearnVault is IERC20 { 
    function deposit(uint256 _tokenAmount) external;

    function withdraw(uint256 _tokenAmount) external;

    function calcTokenToYToken(uint256 _tokenAmount) external pure returns (uint256); 

    function calcYTokenToToken(uint256 _yTokenAmount) external pure returns (uint256);
}


