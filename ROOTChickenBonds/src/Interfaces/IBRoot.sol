// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.4.23 <0.9.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IBRoot is IERC20 {
    function mint(address _to, uint256 _bLUSDAmount) external;

    function burn(address _from, uint256 _bLUSDAmount) external;
}