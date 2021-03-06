// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Shares is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable token = IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    uint256 public immutable percent = 10;
    uint256 public immutable startBlock = 19251111;
    uint256 public sharesPrice = 0;
    
    event PriceUpdated(uint price);
    event AddedTrusted(address user);
    event RemovedTrusted(address user);
    event SentTo(address user,uint amount);
    
    
    constructor() { }

    function sendTo(address to, uint256 amount) external onlyOwner {
        updatePrice();
        
        uint256 distribution = sharesPrice * amount / 1e18;
        uint256 balance = token.balanceOf(address(this));
        if (distribution > balance) {
            distribution = balance;
        }
        token.safeTransfer(to, distribution);

        emit SentTo(to, amount);
    }

    function updatePrice() public onlyOwner {
        if (sharesPrice < token.balanceOf(address(this)) || startBlock > block.number || sharesPrice == 0) {
            sharesPrice = token.balanceOf(address(this)) * percent / 100;
        }
        
        emit PriceUpdated(sharesPrice);
    }
    
    function firstUpdatePrice() public {
        require(sharesPrice == 0 || startBlock > block.number, "already Set");
        
        sharesPrice = token.balanceOf(address(this)) * percent / 100;
        emit PriceUpdated(sharesPrice);
    }
}
