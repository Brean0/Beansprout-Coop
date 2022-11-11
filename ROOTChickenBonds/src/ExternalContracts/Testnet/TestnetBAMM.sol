// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../Interfaces/IBAMM.sol";

import { IYieldReceiver } from "./Harvester.sol";

contract TestnetBAMM is IBAMM, IYieldReceiver, Ownable {
    IERC20 public immutable beanToken;
    address public chicken;

    uint256 private _lusdValue;

    constructor(address _lusdTokenAddress) {
        beanToken = IERC20(_lusdTokenAddress);
    }

    modifier onlyChicken() {
        require(msg.sender == chicken, "TestnetBAMM: caller is not the chicken");
        _;
    }

    function deposit(uint256 _beanAmount) external onlyChicken {
        _lusdValue += _beanAmount;
        beanToken.transferFrom(msg.sender, address(this), _beanAmount);
    }

    function withdraw(uint256 _beanAmount, address _to) external onlyChicken {
        _lusdValue -= _beanAmount;
        beanToken.transfer(_to, _beanAmount);
    }

    function swap(uint beanAmount, uint minEthReturn, address payable dest) public returns(uint) {}

    function getSwapEthAmount(uint lusdQty) public view returns(uint ethAmount, uint feeLusdAmount) {}

    function getLUSDValue()
        external
        view
        returns (
            uint256 totalLUSDValue,
            uint256 lusdBalance,
            uint256 ethLUSDValue
        )
    {
        totalLUSDValue = _lusdValue;
        lusdBalance = _lusdValue;
        ethLUSDValue = 0;
    }

    function setChicken(address _chicken) external onlyOwner {
        chicken = _chicken;
    }

    function _notifyYield(uint256 _amount) external onlyOwner {
        require(
            beanToken.balanceOf(address(this)) >= _lusdValue + _amount,
            "TestnetBAMM: yield more than LUSD balance increase"
        );

        _lusdValue += _amount;
    }

    function _getCurrentValue() external view returns (uint256) {
        return _lusdValue;
    }
}
