// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;


interface IBAMM {
    function deposit(uint256 beanAmount) external;

    function withdraw(uint256 beanAmount, address to) external;

    function swap(uint beanAmount, uint minEthReturn, address payable dest) external returns(uint);

    function getSwapEthAmount(uint lusdQty) external view returns(uint ethAmount, uint feeLusdAmount);

    function getLUSDValue() external view returns (uint256, uint256, uint256);

    function setChicken(address _chicken) external;
}
