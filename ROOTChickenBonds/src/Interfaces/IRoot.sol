// SPDX-License-Identifier: MIT
pragma solidity >=0.4.23 <0.9.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IRoot is IERC20 { 


    // --- Functions ---

    function mint(address _account, uint256 _amount) external;

    function burn(address _account, uint256 _amount) external;

    function sendToPool(address _sender,  address poolAddress, uint256 _amount) external;

    function returnFromPool(address poolAddress, address user, uint256 _amount ) external;

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function bdvPerRoot() external view returns (uint256);
}
