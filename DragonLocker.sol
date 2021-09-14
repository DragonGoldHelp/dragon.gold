// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract DragonLocker {
    // using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public DGold;

    uint256 public startReleaseBlock;
    uint256 public endReleaseBlock;

    uint256 private _totalLock;
    mapping(address => uint256) private _locks;
    mapping(address => uint256) private _released;

    event Lock(address indexed to, uint256 value);

    constructor(IERC20 d) public {
        DGold = d;
        startReleaseBlock = 19814589;
        endReleaseBlock = 20378067;
    }

    function totalLock() external view returns (uint256) {
        return _totalLock;
    }
    
    function getStartReleaseBlock() external view returns (uint256) {
        return startReleaseBlock;
    }    

    function lockOf(address _account) external view returns (uint256) {
        return _locks[_account];
    }

    function released(address _account) external view returns (uint256) {
        return _released[_account];
    }

    function lock(address _account, uint256 _amount) external {
        require(block.number < startReleaseBlock, "no more lock");
        require(_account != address(0), "no lock to address(0)");
        require(_amount > 0, "zero lock");

        DGold.safeTransferFrom(msg.sender, address(this), _amount);

        _locks[_account] = _locks[_account] + _amount;
        _totalLock = _totalLock + _amount;

        emit Lock(_account, _amount);
    }

    function canUnlockAmount(address _account) public view returns (uint256) {
        if (block.number < startReleaseBlock) {
            return 0;
        } else if (block.number >= endReleaseBlock) {
            return _locks[_account] - _released[_account];
        } else {
            uint256 _releasedBlock = block.number - startReleaseBlock;
            uint256 _totalVestingBlock = endReleaseBlock - startReleaseBlock;
            return _locks[_account] * _releasedBlock / _totalVestingBlock - _released[_account];
        }
    }

    function unlock() external {
        require(block.number > startReleaseBlock, "still locked");
        require(_locks[msg.sender] > _released[msg.sender], "no locked");

        uint256 _amount = canUnlockAmount(msg.sender);

        DGold.safeTransfer(msg.sender, _amount);
        _released[msg.sender] = _released[msg.sender] + _amount;
        _totalLock = _totalLock - _amount;
    }

}