/* Copyright (C) 2020 PlotX.io
  This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.
  This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.
  You should have received a copy of the GNU General Public License
    along with this program.  If not, see http://www.gnu.org/licenses/ */

pragma solidity 0.5.7;

import "./external/openzeppelin-solidity/math/SafeMath.sol";
import "./external/openzeppelin-solidity/token/ERC20/ERC20.sol";
import "./external/NativeMetaTransaction.sol";


contract Staking is NativeMetaTransaction {
    
    using SafeMath for uint256;

    /**
     * @dev Structure to store Interest details.
     * It contains total amount of tokens staked and globalYield.
     */
    struct InterestData {
        uint256 globalTotalStaked;
        uint256 globalYieldPerToken; 
        uint256 lastUpdated;
        mapping(address => Staker) stakers;  
    }

    /**
     * @dev Structure to store staking details.
     * It contains amount of tokens staked and withdrawn interest.
     */
    struct Staker {
        uint256 totalStaked;
        uint256 withdrawnToDate;
        uint256 stakeBuyinRate;  
    }


    // Token address
    ERC20 private stakeToken;

    // Reward token
    ERC20 private rewardToken;

    // Interest and staker data
    InterestData public interestData;

    uint public stakingStartTime;

    uint public totalReward;

    // unclaimed reward will be trasfered to this account
    address public vaultAddress; 

    // 10^18
    uint256 private constant DECIMAL1e18 = 10**18;

    //Total time (in sec) over which reward will be distributed
    uint256 public stakingPeriod;

    uint256 public minStake; 

    uint256 public fees;

    uint8 public bplotRewardPerc;

    address public bplot;

    address public authorised;


    /**
     * @dev Emitted when `staker` stake `value` tokens.
     */
    event Staked(address indexed staker, uint256 value, uint256 _globalYieldPerToken);

    event BatchStaking(address caller, address[] indexed stakers, uint256[] values, uint totalStakeInBatch, uint256 indexed _date);

    /**
     * @dev Emitted when `staker` withdraws their stake `value` tokens.
     */
    event StakeWithdrawn(address indexed staker, uint256 value, uint256 _globalYieldPerToken);

    /*
     * @dev Emitted when bplot is rewarded to staker
    */
    event BplotRewarded(address indexed staker, uint256 value, uint256 feesDeducted);


    /**
     * @dev Emitted when `staker` collects interest `_value`.
     */
    event InterestCollected(
        address indexed staker,
        uint256 _value,
        uint256 _globalYieldPerToken
    );

    /**     
     * @dev Constructor     
     * @param _stakeToken The address of stake Token       
     * @param _rewardToken The address of reward Token   
     * @param _stakingPeriod valid staking time after staking starts
     * @param _totalRewardToBeDistributed total amount to be distributed as reward
     */
    constructor(
        address _stakeToken,
        address _rewardToken,
        uint256 _stakingPeriod,
        uint256 _totalRewardToBeDistributed,
        uint256 _stakingStart,
        address _vaultAdd,
        address _bplot,
        uint256 _minStake,
        uint256 _fees,
        uint8 _bplotRewardsPerc,
        address _authorised
    ) public {
        require(_stakingPeriod > 0, "Should be positive");
        require(_totalRewardToBeDistributed > 0, "Total reward can not be 0");
        require(_stakingStart >= now, "Can not be past time");
        require(_stakeToken != address(0), "Can not be null address");
        require(_rewardToken != address(0), "Can not be null address");
        require(_vaultAdd != address(0), "Can not be null address");
        stakeToken = ERC20(_stakeToken);
        rewardToken = ERC20(_rewardToken);
        stakingStartTime = _stakingStart;
        interestData.lastUpdated = _stakingStart;
        stakingPeriod = _stakingPeriod;
        totalReward = _totalRewardToBeDistributed;
        vaultAddress = _vaultAdd;
        minStake = _minStake;
        fees = _fees;
        bplotRewardPerc = _bplotRewardsPerc;
        bplot = _bplot;
        authorised = _authorised;
        _initializeEIP712("Staking");
    }

    /**
     * @dev Allows a staker to deposit Tokens. Notice that `approve` is
     * needed to be executed before the execution of this method.
     * @param _amount The amount of tokens to stake
     */
    function stake(uint256 _amount) external {
        address payable _msgSender = _msgSender();
        require(
            stakeToken.transferFrom(_msgSender, address(this), _amount),
            "TransferFrom failed, make sure you approved token transfer"
        );
        _stake(_msgSender, _amount);
    }

    function stakeFor(address[] calldata _users, uint256[] calldata _amounts, uint256 _totalStakeInBatch, uint256 _date) external {
        address payable _msgSender = _msgSender();
        require(_users.length == _amounts.length,"Array length mismatch");
        require(
            stakeToken.transferFrom(_msgSender, address(this), _totalStakeInBatch),
            "TransferFrom failed, make sure you approved token transfer"
        );
        uint totalStake = 0;
        for(uint i=0;i<_users.length;i++){
            totalStake = totalStake.add(_amounts[i]);
            _stake(_users[i], _amounts[i]);
        }
        require(_totalStakeInBatch == totalStake,"Incorrect payment");
        emit BatchStaking(_msgSender, _users, _amounts, _totalStakeInBatch, _date);
    }

    function _stake(address _user, uint256 _amount) internal {
        require(_user != address(0),"Can't be null address");
        require(_amount > minStake, "You need to stake minimum amount");
        require(now.sub(stakingStartTime) <= stakingPeriod, "Can not stake after staking period passed");
        uint newlyInterestGenerated = now.sub(interestData.lastUpdated).mul(totalReward).div(stakingPeriod);
        interestData.lastUpdated = now;
        uint feeMultiplier = 1; // 2 if user's 1st stake else 1
        if(interestData.stakers[_user].totalStaked == 0) {
            feeMultiplier = 2;
        }
        updateGlobalYieldPerToken(newlyInterestGenerated);
        updateStakeData(_user, _amount);
        uint bplotReward = _amount.mul(bplotRewardPerc).div(100);
        ERC20(bplot).transfer(_user,bplotReward.sub(fees.mul(feeMultiplier)));
        
        emit BplotRewarded(_user, bplotReward, fees);
        emit Staked(_user, _amount, interestData.globalYieldPerToken);
    }

    /**
     * @dev Updates InterestData and Staker data while staking.
     * must call update globalYieldPerToken before this operation
     * @param _staker                 Staker's address
     * @param _stake                  Amount of stake
     *
     */
    function updateStakeData(
        address _staker,
        uint256 _stake
    ) internal {
        Staker storage _stakerData = interestData.stakers[_staker];

        _stakerData.totalStaked = _stakerData.totalStaked.add(_stake);

        updateStakeBuyinRate(
            _stakerData,
            interestData.globalYieldPerToken,
            _stake
        );

        interestData.globalTotalStaked = interestData.globalTotalStaked.add(_stake);
    }

    /**
     * @dev Calculates and updates the yield rate in which the staker has entered
     * a staker may stake multiple times, so we calculate his cumulative rate his earning will be calculated based on GlobalYield and StakeBuyinRate
     * Formula:
     * StakeBuyinRate = [StakeBuyinRate(P) + (GlobalYield(P) x Stake)]
     *
     * @param _stakerData                  Staker's Data
     * @param _globalYieldPerToken         Total yielding amount per token 
     * @param _stake                       Amount staked 
     *
     */
    function updateStakeBuyinRate(
        Staker storage _stakerData,
        uint256 _globalYieldPerToken,
        uint256 _stake
    ) internal {

        _stakerData.stakeBuyinRate = _stakerData.stakeBuyinRate.add(
            _globalYieldPerToken.mul(_stake).div(DECIMAL1e18)
        );
    }

    /**
     * @dev Withdraws the sender staked Token.
     */
    function withdrawStakeAndInterest(uint256 _amount) external {
        require(now.sub(stakingStartTime) > stakingPeriod, "Still locked");
        address payable _msgSender = _msgSender();
        Staker storage staker = interestData.stakers[_msgSender];
        require(_amount > 0, "Should withdraw positive amount");
        require(staker.totalStaked >= _amount, "Not enough token staked");
        withdrawInterest();
        updateStakeAndInterestData(_msgSender, _amount);
        require(stakeToken.transfer(_msgSender, _amount), "withdraw transfer failed");
        emit StakeWithdrawn(_msgSender, _amount, interestData.globalYieldPerToken);
    }
    
    /**
     * @dev Updates InterestData and Staker data while withdrawing stake.
     *
     * @param _staker                 Staker address
     * @param _amount                 Amount of stake to withdraw
     *
     */    
    function updateStakeAndInterestData(
        address _staker,
        uint256 _amount
    ) internal {
        Staker storage _stakerData = interestData.stakers[_staker];

        _stakerData.totalStaked = _stakerData.totalStaked.sub(_amount);

        interestData.globalTotalStaked = interestData.globalTotalStaked.sub(_amount);

        _stakerData.stakeBuyinRate = 0;
        _stakerData.withdrawnToDate = 0;
        updateStakeBuyinRate(
            _stakerData,
            interestData.globalYieldPerToken,
            _stakerData.totalStaked
        );
    }

    /**
     * @dev Withdraws the sender Earned interest.
     */
    function withdrawInterest() public {
        require(now.sub(stakingStartTime) > stakingPeriod, "Still locked");
        address payable _msgSender = _msgSender();
        uint timeSinceLastUpdate = _timeSinceLastUpdate();
        uint newlyInterestGenerated = timeSinceLastUpdate.mul(totalReward).div(stakingPeriod);
        
        updateGlobalYieldPerToken(newlyInterestGenerated);
        uint256 interest = calculateInterest(_msgSender);
        Staker storage stakerData = interestData.stakers[_msgSender];
        stakerData.withdrawnToDate = stakerData.withdrawnToDate.add(interest);
        require(rewardToken.transfer(_msgSender, interest), "Withdraw interest transfer failed");
        emit InterestCollected(_msgSender, interest, interestData.globalYieldPerToken);
    }

    function updateGlobalYield() public {
        uint timeSinceLastUpdate = _timeSinceLastUpdate();
        uint newlyInterestGenerated = timeSinceLastUpdate.mul(totalReward).div(stakingPeriod);
        updateGlobalYieldPerToken(newlyInterestGenerated);
    }

    function getYieldData(address _staker) public view returns(uint256, uint256)
    {

      return (interestData.globalYieldPerToken, interestData.stakers[_staker].stakeBuyinRate);
    }

    function _timeSinceLastUpdate() internal returns(uint256) {
        uint timeSinceLastUpdate;
        if(now.sub(stakingStartTime) > stakingPeriod)
        {
            timeSinceLastUpdate = stakingStartTime.add(stakingPeriod).sub(interestData.lastUpdated);
            interestData.lastUpdated = stakingStartTime.add(stakingPeriod);
        } else {
            timeSinceLastUpdate = now.sub(interestData.lastUpdated);
            interestData.lastUpdated = now;
        }
        return timeSinceLastUpdate;
    }

    /**
     * @dev Calculates Interest for staker for their stake.
     *
     * Formula:
     * EarnedInterest = MAX[TotalStaked x GlobalYield - (StakeBuyinRate + WithdrawnToDate), 0]
     *
     * @param _staker                     Staker's address
     *
     * @return The amount of tokens credit for the staker.
     */
    function calculateInterest(address _staker)
        public
        view
        returns (uint256)
    {
        Staker storage stakerData = interestData.stakers[_staker];

        
        uint256 _withdrawnToDate = stakerData.withdrawnToDate;

        uint256 intermediateInterest = stakerData
            .totalStaked
            .mul(interestData.globalYieldPerToken).div(DECIMAL1e18);

        uint256 intermediateVal = _withdrawnToDate.add(
            stakerData.stakeBuyinRate
        );

        // will lead to -ve value
        if (intermediateVal > intermediateInterest) {
            return 0;
        }

        uint _earnedInterest = (intermediateInterest.sub(intermediateVal));

        return _earnedInterest;
    }

    /**
     * @dev Calculates and updates new accrued amount per token since last update.
     *
     * Formula:
     * GlobalYield = GlobalYield(P) + newlyGeneratedInterest/GlobalTotalStake.
     *
     * @param _interestGenerated  Interest token earned since last update.
     *
     */
    function updateGlobalYieldPerToken(
        uint256 _interestGenerated
    ) internal {
        if (interestData.globalTotalStaked == 0) {
            require(rewardToken.transfer(vaultAddress, _interestGenerated), "Transfer failed while trasfering to vault");
            return;
        }
        interestData.globalYieldPerToken = interestData.globalYieldPerToken.add(
            _interestGenerated
                .mul(DECIMAL1e18) 
                .div(interestData.globalTotalStaked) 
        );
    }


    function getStakerData(address _staker) public view returns(uint256, uint256)
    {

      return (interestData.stakers[_staker].totalStaked, interestData.stakers[_staker].withdrawnToDate);
    }

    /**
     * @dev returns stats data.
     * @param _staker Address of staker.
     * @return Total staked.
     * @return Total reward to be distributed.
     * @return estimated reward for user at end of staking period if no one stakes from current time.
     * @return Unlocked reward based on elapsed time.
     * @return Accrued reward for user till now.
     */
    function getStatsData(address _staker) external view returns(uint, uint, uint, uint, uint)
    {

        Staker storage stakerData = interestData.stakers[_staker];
        uint estimatedReward = 0;
        uint unlockedReward = 0;
        uint accruedReward = 0;
        uint timeElapsed = now.sub(stakingStartTime);

        if(timeElapsed > stakingPeriod)
        {
            timeElapsed = stakingPeriod;
        }

        unlockedReward = timeElapsed.mul(totalReward).div(stakingPeriod);

        uint timeSinceLastUpdate;
        if(timeElapsed == stakingPeriod)
        {
            timeSinceLastUpdate = stakingStartTime.add(stakingPeriod).sub(interestData.lastUpdated);
        } else {
            timeSinceLastUpdate = now.sub(interestData.lastUpdated);
        }
        uint newlyInterestGenerated = timeSinceLastUpdate.mul(totalReward).div(stakingPeriod);
        uint updatedGlobalYield;
        uint stakingTimeLeft = 0;
        if(now < stakingStartTime.add(stakingPeriod)){
         stakingTimeLeft = stakingStartTime.add(stakingPeriod).sub(now);
        }
        uint interestGeneratedEnd = stakingTimeLeft.mul(totalReward).div(stakingPeriod);
        uint globalYieldEnd;
        if (interestData.globalTotalStaked != 0) {
            updatedGlobalYield = interestData.globalYieldPerToken.add(
            newlyInterestGenerated
                .mul(DECIMAL1e18)
                .div(interestData.globalTotalStaked));

            globalYieldEnd = updatedGlobalYield.add(interestGeneratedEnd.mul(DECIMAL1e18).div(interestData.globalTotalStaked));
        }
        
        accruedReward = stakerData
            .totalStaked
            .mul(updatedGlobalYield).div(DECIMAL1e18);

        if (stakerData.withdrawnToDate.add(stakerData.stakeBuyinRate) > accruedReward)
        {
            accruedReward = 0;
        } else {

            accruedReward = accruedReward.sub(stakerData.withdrawnToDate.add(stakerData.stakeBuyinRate));
        }

        estimatedReward = stakerData
            .totalStaked
            .mul(globalYieldEnd).div(DECIMAL1e18);
        if (stakerData.withdrawnToDate.add(stakerData.stakeBuyinRate) > estimatedReward) {
            estimatedReward = 0;
        } else {

            estimatedReward = estimatedReward.sub(stakerData.withdrawnToDate.add(stakerData.stakeBuyinRate));
        }

        return (interestData.globalTotalStaked, totalReward, estimatedReward, unlockedReward, accruedReward);

    }

    function updateConfigParams(bytes8 _code, uint256 _val) public {
        require(msg.sender == authorised,"Not authorised to update");
        if(_code == "MS") {
            minStake = _val;
        } else if(_code == "FEES") {
            fees = _val;
        } else if(_code == "BRP") {
            require(_val <= 100, "Should be less than 100");
            require(uint8(_val) == _val, "Value is Overflowing");
            bplotRewardPerc = uint8(_val);
        } else {
            revert("Invalid code");
        }
    }

    function updateAuthAddress(address _newAuth) public {
        require(msg.sender == authorised,"Not authorised to update");
        // not adding null address check because null address is allowed to renounce auth address
        authorised = _newAuth;
    }


}
