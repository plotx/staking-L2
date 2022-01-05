pragma solidity 0.5.7;

import "../Staking.sol";

contract MockStaking is Staking {

  constructor(address _stakeToken, 
    address _rewardToken, 
    uint256 stakingPeriod, 
    uint256 _totalRewardToBeDistributed, 
    uint256 startTime, 
    address vaultAdd, 
    address _bplot,
    uint256 _minStake,
    uint256 _fees,
    uint8 _bplotRewardsPerc,
    address _authorised) public 
  Staking(_stakeToken, 
    _rewardToken, 
    stakingPeriod, 
    _totalRewardToBeDistributed, 
    startTime, 
    vaultAdd, 
    _bplot,
    _minStake,
    _fees,
    _bplotRewardsPerc,
    _authorised) {
  }

	function setBuyInRate(address _user, uint _value) public
  {
    interestData.stakers[_user].stakeBuyinRate = _value;
  }

  function addStake(address _user, uint _value) public
  {
    interestData.stakers[_user].totalStaked = _value; 
  }  

  function setInterestData(uint a, uint b) public {
    interestData.globalTotalStaked = a;
    interestData.globalYieldPerToken = b;
  }

  function setStarttime() public {
    stakingStartTime = now;
  }

}