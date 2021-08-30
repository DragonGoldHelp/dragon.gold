// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./DGoldToken.sol";



interface IShares {
    function sendTo(address to, uint256 amount) external;
    function updatePrice() external;
}

contract MasterChef is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardKept;
        uint256 rewardDebt;     // Reward debt. See explanation below.
        uint256 rewardSharesKept;
        uint256 rewardSharesDebt;     // Reward debt. See explanation below.
        uint256 lastClaimedBlock;  // last powered Block
    }

    // Info of each pool.
    struct PoolInfo {
        uint256 amount;
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. SHs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that Shs distribution occurs.
        uint256 accShPerPower;   // Accumulated Shs per share, times 1e12. See below.
        uint16 depositFeeBP;      // Deposit fee in basis points

        uint256 lastSharesRewardBlock;  // Last block number that Shs distribution occurs.
        uint256 accSharesPerPower;   // Accumulated Shs per share, times 1e12. See below.
    }

    DGoldToken public sh;
    IShares public shares;
    // Dev address.
    address public devaddr;
    // SH tokens created per block.
    uint256 public shPerBlock = 1e18;

    // Deposit Fee address
    address public feeAddress;
    address public sharesAddress;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Block number in which the user made token withdrawal from pool 0
    mapping (address => uint) public lastTokenWithdrawBlock;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when Sh mining starts.
    uint256 public startBlock;

    // Referrers
    mapping (address => address) public referrer;
    mapping (address => mapping (uint8 => uint)) public referrals;
    mapping (address => uint) public referrerReward;
    uint16[] public referrerRewardRate = [ 600, 300, 100 ];

    mapping(IERC20 => bool) public poolExistence;
    modifier nonDuplicated(IERC20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated:duplicated");
        _;
    }


    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Claim(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    
    event AddPool(uint256 _allocPoint, IERC20 _lpToken, uint16 _depositFeeBP, bool _withUpdate);
    event SetPool(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate);
    
    event SetDev(address dev);
    event SetFee(address fee);
    event UpdateEmissionRate(uint256 _shPerBlock);
    
    event Reinvest(address indexed user, uint256 _pid);
    event ClaimShares(address indexed user, uint256 _pid);

    constructor (
        DGoldToken _sh,
        IShares _shares,
        address _devaddr,
        address _feeAddress,
        address _sharesAddress,
        uint256 _startBlock,
        uint256 _shAllocPoint
    ) {
        require(_devaddr != address(0), "address can't be 0");
        require(_feeAddress != address(0), "address can't be 0");

        sh = _sh;
        shares = _shares;
        devaddr = _devaddr;
        feeAddress = _feeAddress;
        sharesAddress = _sharesAddress;
        startBlock = _startBlock;

        totalAllocPoint = _shAllocPoint;
        poolInfo.push(PoolInfo({
            amount: 0,
            lpToken: _sh,
            allocPoint: _shAllocPoint,
            lastRewardBlock: startBlock,
            accShPerPower: 0,
            depositFeeBP: 0,
            lastSharesRewardBlock: startBlock,
            accSharesPerPower: 0
        }));
    }

    function poolLength() external view returns (uint) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IERC20 _lpToken, uint16 _depositFeeBP, bool _withUpdate) nonDuplicated(_lpToken) external onlyOwner {
        require(_depositFeeBP <= 500, "add: invalid deposit fee basis points");
        if (_withUpdate) {
            _massUpdatePools();
        }
        
        _lpToken.balanceOf(address(this));
        
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint += _allocPoint;
        poolInfo.push(PoolInfo({
            amount:0,
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accShPerPower: 0,
            depositFeeBP: _depositFeeBP,
            lastSharesRewardBlock: lastRewardBlock,
            accSharesPerPower: 0
        }));
        
        emit AddPool(_allocPoint, _lpToken, _depositFeeBP, _withUpdate);
    }

    // Update the given pool's SH allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) external onlyOwner {
        require(_depositFeeBP <= 500, "set: invalid deposit fee basis points");
        if (_withUpdate) {
            _massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
        
        emit SetPool(_pid, _allocPoint, _depositFeeBP, _withUpdate);
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) external {
        require(msg.sender == devaddr, "dev: wut?");
        require(_devaddr != address(0), "!nonzero");
        
        devaddr = _devaddr;
        
        emit SetDev(_devaddr);
    }

    function setFeeAddress(address _feeAddress) external {
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
        require(_feeAddress != address(0), "!nonzero");
        
        feeAddress = _feeAddress;
        
        emit SetFee(_feeAddress);
    }

    //Pancake has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _shPerBlock) external onlyOwner {
        require(_shPerBlock <= 100,"Too high");
        
        _massUpdatePools();
        shPerBlock = _shPerBlock;
        
        emit UpdateEmissionRate(_shPerBlock);
    }

    // View function to see pending SHs on frontend.
    function pendingSh(uint256 _pid, address _user) external view returns (uint) {
        UserInfo storage user = userInfo[_pid][_user];
        return (user.rewardKept + _pendingSh(_pid, _user)) * (100 + aprMultiplier(_pid, _user)) / 100;
    }

    // View function to see pending SHs on frontend.
    function pendingShares(uint256 _pid, address _user) external view returns (uint) {
        UserInfo storage user = userInfo[_pid][_user];
        return user.rewardSharesKept + _pendingShares(_pid, _user);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function _massUpdatePools() internal {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            _updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function _updatePool(uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        if (pool.amount == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            pool.lastSharesRewardBlock = block.number;
            return;
        }

        uint256 blockAmount = block.number - pool.lastRewardBlock;
        uint256 shReward = blockAmount * shPerBlock * pool.allocPoint / totalAllocPoint;
        sh.mint(devaddr, shReward / 10);
        sh.mint(address(this), shReward);
        pool.accShPerPower += shReward * 1e12 / pool.amount;
        pool.lastRewardBlock = block.number;

        uint256 sharesMultiplier = (block.number - pool.lastSharesRewardBlock) / 74000;
        if (sharesMultiplier > 0) {
            uint256 sharesReward = 1e18 * sharesMultiplier / 3;
            pool.accSharesPerPower += sharesReward * 1e12 / pool.amount;
            pool.lastSharesRewardBlock = block.number;
        }
    }

    // Deposit LP tokens to MasterChef for SH allocation.
    function deposit(uint256 _pid, uint256 _amount, address _ref) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        _updatePool(_pid);
        _keepPendingShAndShares(_pid, msg.sender);
        uint256 balance = pool.lpToken.balanceOf(address(this));
        
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            

            uint256 amount = pool.lpToken.balanceOf(address(this)) - balance;
            
            if(pool.depositFeeBP > 0){
                uint256 depositFee = amount * pool.depositFeeBP / 10000;
                uint256 feeAddressAmount = depositFee * 3/5;
                pool.lpToken.safeTransfer(feeAddress, feeAddressAmount);
                pool.lpToken.safeTransfer(sharesAddress, depositFee - feeAddressAmount);
                shares.updatePrice();
                amount -= depositFee;
            }
            
            user.amount += amount;
            pool.amount += amount;
        }

        user.rewardDebt = user.amount * pool.accShPerPower / 1e12;
        user.rewardSharesDebt = user.amount * pool.accSharesPerPower / 1e12;

        if (user.lastClaimedBlock == 0) {
            user.lastClaimedBlock = block.number;
        }

        if (_ref != address(0) && _ref != msg.sender && referrer[msg.sender] == address(0)) {
            referrer[msg.sender] = _ref;

            // direct ref
            referrals[_ref][0] += 1;
            referrals[_ref][1] += referrals[msg.sender][0];
            referrals[_ref][2] += referrals[msg.sender][1];

            // direct refs from direct ref
            address ref1 = referrer[_ref];
            if (ref1 != address(0)) {
                referrals[ref1][1] += 1;
                referrals[ref1][2] += referrals[msg.sender][0];

                // their refs
                address ref2 = referrer[ref1];
                if (ref2 != address(0)) {
                    referrals[ref2][2] += 1;
                }
            }
        }

        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        _updatePool(_pid);
        _keepPendingShAndShares(_pid, msg.sender);

        if (_amount > 0) {
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
            user.amount -= _amount;
            pool.amount -= _amount;
        }

        user.rewardDebt = user.amount * pool.accShPerPower / 1e12;
        user.rewardSharesDebt = user.amount * pool.accSharesPerPower / 1e12;

        if (_pid == 0) {
            lastTokenWithdrawBlock[msg.sender] = block.number;
        }

        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERSHCY ONLY.
    function emergencyWithdraw(uint256 _pid) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        pool.amount -= user.amount;
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        user.rewardKept = 0;
        user.rewardSharesDebt = 0;
        user.rewardSharesKept = 0;

        if (_pid == 0) {
            lastTokenWithdrawBlock[msg.sender] = block.number;
        }

        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    function _rewardReferrers(uint256 baseAmount) internal {
        address ref = msg.sender;
        for (uint8 i = 0; i < referrerRewardRate.length; i++) {
            ref = referrer[ref];
            if (ref == address(0)) {
                break;
            }

            uint256 reward = baseAmount * referrerRewardRate[i] / 10000;
            sh.mint(ref, reward);
            referrerReward[ref] += reward;
        }
    }
    
    function aprMultiplier(uint256 _pid, address sender) public view returns (uint) {
        UserInfo storage user = userInfo[_pid][sender];
        uint256 multiplier = (block.number - Math.max(lastTokenWithdrawBlock[sender], user.lastClaimedBlock)) * 10 / 28800; //10% per 24 hours
        if (multiplier > 50) {
            multiplier = 50;
        }
        
        return multiplier;
    }

    function claim(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        _updatePool(_pid);

        uint256 pending = user.rewardKept + _pendingSh(_pid, msg.sender);

        require(pending > 0, "Nothing to claim");

        _safeShTransfer(msg.sender, pending);
        _rewardReferrers(pending);

        uint256 multiplier = aprMultiplier(_pid, msg.sender);
        
        if (multiplier > 0) {
            sh.mint(msg.sender, pending * multiplier / 100);
        }

        emit Claim(msg.sender, _pid, pending + pending * multiplier / 100);

        user.rewardKept = 0;
        user.rewardDebt = user.amount * pool.accShPerPower / 1e12;
        user.lastClaimedBlock = block.number;
    }

    function reinvest(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        _updatePool(_pid);

        uint256 pending = user.rewardKept + _pendingSh(_pid, msg.sender);

        require(pending > 0, "Nothing to claim");

        _rewardReferrers(pending);

        uint256 multiplier = aprMultiplier(_pid, msg.sender);
        
        if (multiplier > 0) {
            sh.mint(address(this), pending * multiplier / 100);
        }

        user.rewardKept = 0;
        user.rewardDebt = user.amount * pool.accShPerPower / 1e12;

        // adding to pool 0
        uint256 _amount = pending + pending * multiplier / 100;

        PoolInfo storage reinvestPool = poolInfo[0];
        UserInfo storage reinvestUser = userInfo[0][msg.sender];

        _updatePool(0);
        _keepPendingShAndShares(0, msg.sender);

        reinvestPool.amount += _amount;
        reinvestUser.amount += _amount;
        reinvestUser.rewardDebt = reinvestUser.amount * reinvestPool.accShPerPower / 1e12;
        reinvestUser.rewardSharesDebt = reinvestUser.amount * reinvestPool.accSharesPerPower / 1e12;
        
        emit Reinvest(msg.sender, _pid);
    }


    function claimShares(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        _updatePool(_pid);

        uint256 pending = user.rewardSharesKept + _pendingShares(_pid, msg.sender);

        require(pending > 0, "Nothing to claim");

        shares.sendTo(msg.sender, pending);

        user.rewardSharesKept = 0;
        user.rewardSharesDebt = user.amount * pool.accSharesPerPower / 1e12;
        
        emit ClaimShares(msg.sender, _pid);
    }

    function _keepPendingShAndShares(uint256 _pid, address _user) internal {
        UserInfo storage user = userInfo[_pid][_user];
        user.rewardKept += _pendingSh(_pid, _user);
        user.rewardSharesKept += _pendingShares(_pid, _user);
    }

    // DO NOT includes kept reward
    function _pendingSh(uint256 _pid, address _user) internal view returns (uint) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accShPerPower = pool.accShPerPower;

        if (block.number > pool.lastRewardBlock && pool.amount != 0 && totalAllocPoint > 0) {
            uint256 blockAmount = block.number - pool.lastRewardBlock;
            uint256 shReward = blockAmount * shPerBlock * pool.allocPoint / totalAllocPoint;
            accShPerPower += shReward * 1e12 / pool.amount;
        }

        return user.amount * accShPerPower / 1e12 - user.rewardDebt;
    }

    // DO NOT includes kept reward
    function _pendingShares(uint256 _pid, address _user) internal view returns (uint) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accSharesPerPower = pool.accSharesPerPower;

        if (_pid > 2) {
            return 0;
        }

        if (block.number > pool.lastSharesRewardBlock && pool.amount != 0 && totalAllocPoint > 0) {
            uint256 blockAmount = (block.number - pool.lastSharesRewardBlock) / 74000;
            uint256 sharesReward = blockAmount * 1e18 / 3;
            accSharesPerPower += sharesReward * 1e12 / pool.amount;
        }

        return user.amount * accSharesPerPower / 1e12 - user.rewardSharesDebt;
    }

    // Safe sh transfer function, just in case if rounding error causes pool to not have enough SHs.
    function _safeShTransfer(address _to, uint256 _amount) internal {
        uint256 shBal = sh.balanceOf(address(this));
        if (_amount > shBal) {
            sh.transfer(_to, shBal);
        } else {
            sh.transfer(_to, _amount);
        }
    }
}
