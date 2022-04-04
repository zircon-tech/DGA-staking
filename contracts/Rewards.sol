// SPDX-License-Identifier: GPLv2

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./AccessControls.sol";
import "./DKeeper.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./Utils/UniswapV2Library.sol";

/**
 * @title DKeeper Rewards
 * @dev Calculates the rewards for staking on the DGA platform
 * @author ZirconTech
 * @author Attr: Adrian Guerrera (deepyr)
 */

interface DKeeperStaking {
    function stakedEthTotal() external view returns (uint256);
    function lpToken() external view returns (address);
    function WETH() external view returns (address);
}

interface KEEP is IERC20 {
    function mint(address tokenOwner, uint tokens) external returns (bool);
}

contract Rewards {
    using SafeMath for uint256;

    /* ========== Variables ========== */

    KEEP public rewardsToken;
    AccessControls public accessControls;
    DKeeperStaking public genesisStaking;

    uint256 public constant POINT_MULTIPLIER = 10e18;
    uint256 public constant SECONDS_PER_DAY = 24 * 60 * 60;
    uint256 public constant SECONDS_PER_WEEK = 7 * 24 * 60 * 60;
    
    // weekNumber => rewards
    mapping (uint256 => uint256) public weeklyRewardsPerSecond;
    mapping (address => mapping(uint256 => uint256)) public weeklyBonusPerSecond;

    uint256 public startTime;
    uint256 public lastRewardTime;

    uint256 public genesisRewardsPaid;

    /* ========== Structs ========== */

    struct Weights {
        uint256 genesisWtPoints;
    }

    /// @notice mapping of a staker to its current properties
    mapping (uint256 => Weights) public weeklyWeightPoints;

    /* ========== Events ========== */

    event RewardAdded(address indexed addr, uint256 reward);
    event RewardDistributed(address indexed addr, uint256 reward);
    event Recovered(address indexed token, uint256 amount);

    
    /* ========== Admin Functions ========== */
    constructor(
        KEEP _rewardsToken,
        AccessControls _accessControls,
        DKeeperStaking _genesisStaking,
        uint256 _startTime,
        uint256 _lastRewardTime,
        uint256 _genesisRewardsPaid,

    )
        public
    {
        rewardsToken = _rewardsToken;
        accessControls = _accessControls;
        genesisStaking = _genesisStaking;
        startTime = _startTime;
        lastRewardTime = _lastRewardTime;
        genesisRewardsPaid = _genesisRewardsPaid;
    }

    /// @dev Setter functions for contract config
    function setStartTime(
        uint256 _startTime,
        uint256 _lastRewardTime
    )
        external
    {
        require(
            accessControls.hasAdminRole(msg.sender),
            "Rewards.setStartTime: Sender must be admin"
        );
        startTime = _startTime;
        lastRewardTime = _lastRewardTime;
    }

    /// @dev Setter functions for contract config
    function setInitialPoints(
        uint256 week,
        uint256 gW,

    )
        external
    {
        require(
            accessControls.hasAdminRole(msg.sender),
            "Rewards.setStartTime: Sender must be admin"
        );
        Weights storage weights = weeklyWeightPoints[week];
        weights.genesisWtPoints = gW;

    }

    function setGenesisStaking(
        address _addr
    )
        external
    {
        require(
            accessControls.hasAdminRole(msg.sender),
            "Rewards.setGenesisStaking: Sender must be admin"
        );
        require(_addr != address(parentStaking));
        require(_addr != address(lpStaking));
        genesisStaking = DKeeperStaking(_addr);
    }

    /// @notice Set rewards distributed each week
    /// @dev this number is the total rewards that week with 18 decimals
    function setRewards(
        uint256[] memory rewardWeeks,
        uint256[] memory amounts
    )
        external
    {
        require(
            accessControls.hasAdminRole(msg.sender),
            "Rewards.setRewards: Sender must be admin"
        );
        uint256 numRewards = rewardWeeks.length;
        for (uint256 i = 0; i < numRewards; i++) {
            uint256 week = rewardWeeks[i];
            uint256 amount = amounts[i].mul(POINT_MULTIPLIER)
                                       .div(SECONDS_PER_WEEK)
                                       .div(POINT_MULTIPLIER);
            weeklyRewardsPerSecond[week] = amount;
        }
    }
    /// @notice Set rewards distributed each week
    /// @dev this number is the total rewards that week with 18 decimals
    function bonusRewards(
        address pool,
        uint256[] memory rewardWeeks,
        uint256[] memory amounts
    )
        external
    {
        require(
            accessControls.hasAdminRole(msg.sender),
            "Rewards.setRewards: Sender must be admin"
        );
        uint256 numRewards = rewardWeeks.length;
        for (uint256 i = 0; i < numRewards; i++) {
            uint256 week = rewardWeeks[i];
            uint256 amount = amounts[i].mul(POINT_MULTIPLIER)
                                       .div(SECONDS_PER_WEEK)
                                       .div(POINT_MULTIPLIER);
            weeklyBonusPerSecond[pool][week] = amount;
        }
    }

    // From BokkyPooBah's DateTime Library v1.01
    // https://github.com/bokkypoobah/BokkyPooBahsDateTimeLibrary
    function diffDays(uint fromTimestamp, uint toTimestamp) internal pure returns (uint _days) {
        require(fromTimestamp <= toTimestamp);
        _days = (toTimestamp - fromTimestamp) / SECONDS_PER_DAY;
    }


    /* ========== Mutative Functions ========== */

    /// @notice Calculate the current normalised weightings and update rewards
    /// @dev 
    function updateRewards() 
        external
        returns(bool)
    {
        if (block.timestamp <= lastRewardTime) {
            return false;
        }
        uint256 g_net = genesisStaking.stakedEthTotal();

        /// @dev check that the staking pools have contributions, and rewards have started
        if (g_net.add(p_net).add(m_net) == 0 || block.timestamp <= startTime) {
            lastRewardTime = block.timestamp;
            return false;
        }

        uint256 gW = _getReturnWeights(g_net);
        _updateWeightingAcc(gW);

        /// @dev This mints and sends rewards
        _updateGenesisRewards();
        _updateParentRewards();
        _updateLPRewards();

        /// @dev update accumulated reward
        lastRewardTime = block.timestamp;
        return true;
    }


    /* ========== View Functions ========== */

    /// @notice Gets the total rewards outstanding from last reward time
    function totalRewards() external view returns (uint256) {
        uint256 gRewards = genesisRewards(lastRewardTime, block.timestamp);
        return gRewards;
    }


    /// @notice Gets the total contributions from the staked contracts
    function getTotalContributions()
        external
        view
        returns(uint256)
    {
        return genesisStaking.stakedEthTotal();
    }

    /// @dev Getter functions for Rewards contract
    function getCurrentRewardWeek()
        external 
        view 
        returns(uint256)
    {
        return diffDays(startTime, block.timestamp) / 7;
    }

    function totalRewardsPaid()
        external
        view
        returns(uint256)
    {
        return genesisRewardsPaid;
    } 

    /// @notice Return genesis rewards over the given _from to _to timestamp.
    /// @dev A fraction of the start, multiples of the middle weeks, fraction of the end
    function genesisRewards(uint256 _from, uint256 _to) public view returns (uint256 rewards) {
        if (_to <= startTime) {
            return 0;
        }
        if (_from < startTime) {
            _from = startTime;
        }
        uint256 fromWeek = diffDays(startTime, _from) / 7;
        uint256 toWeek = diffDays(startTime, _to) / 7;

       if (fromWeek == toWeek) {
            return _rewardsFromPoints(weeklyRewardsPerSecond[fromWeek],
                                    _to.sub(_from),
                                    weeklyWeightPoints[fromWeek].genesisWtPoints)
                        .add(weeklyBonusPerSecond[address(genesisStaking)][fromWeek].mul(_to.sub(_from)));
        }
        /// @dev First count remainer of first week 
        uint256 initialRemander = startTime.add((fromWeek+1).mul(SECONDS_PER_WEEK)).sub(_from);
        rewards = _rewardsFromPoints(weeklyRewardsPerSecond[fromWeek],
                                    initialRemander,
                                    weeklyWeightPoints[fromWeek].genesisWtPoints)
                        .add(weeklyBonusPerSecond[address(genesisStaking)][fromWeek].mul(initialRemander));

        /// @dev add multiples of the week
        for (uint256 i = fromWeek+1; i < toWeek; i++) {
            rewards = rewards.add(_rewardsFromPoints(weeklyRewardsPerSecond[i],
                                    SECONDS_PER_WEEK,
                                    weeklyWeightPoints[i].genesisWtPoints))
                             .add(weeklyBonusPerSecond[address(genesisStaking)][i].mul(SECONDS_PER_WEEK));
        }
        /// @dev Adds any remaining time in the most recent week till _to
        uint256 finalRemander = _to.sub(toWeek.mul(SECONDS_PER_WEEK).add(startTime));
        rewards = rewards.add(_rewardsFromPoints(weeklyRewardsPerSecond[toWeek],
                                    finalRemander,
                                    weeklyWeightPoints[toWeek].genesisWtPoints))
                          .add(weeklyBonusPerSecond[address(genesisStaking)][toWeek].mul(finalRemander));
        return rewards;
    }

    /* ========== Internal Functions ========== */

    function _updateGenesisRewards() 
        internal
        returns(uint256 rewards)
    {
        rewards = genesisRewards(lastRewardTime, block.timestamp);
        if ( rewards > 0 ) {
            genesisRewardsPaid = genesisRewardsPaid.add(rewards);
            require(rewardsToken.mint(address(genesisStaking), rewards));
        }
    }

    function _rewardsFromPoints(
        uint256 rate,
        uint256 duration, 
        uint256 weight
    ) 
        internal
        pure
        returns(uint256)
    {
        return rate.mul(duration)
            .mul(weight)
            .div(1e18)
            .div(POINT_MULTIPLIER);
    }

    /// @dev Internal fuction to update the weightings 
    function _updateWeightingAcc(uint256 gW) internal {
        uint256 currentWeek = diffDays(startTime, block.timestamp) / 7;
        uint256 lastRewardWeek = diffDays(startTime, lastRewardTime) / 7;
        uint256 startCurrentWeek = startTime.add(currentWeek.mul(SECONDS_PER_WEEK)); 

        /// @dev Initialisation of new weightings and fill gaps
        if (weeklyWeightPoints[0].genesisWtPoints == 0) {
            Weights storage weights = weeklyWeightPoints[0];
            weights.genesisWtPoints = gW;
        }
        /// @dev Fill gaps in weightings
        if (lastRewardWeek < currentWeek ) {
            /// @dev Back fill missing weeks
            for (uint256 i = lastRewardWeek+1; i <= currentWeek; i++) {
                Weights storage weights = weeklyWeightPoints[i];
                weights.genesisWtPoints = gW;
            }
            return;
        }      
        /// @dev Calc the time weighted averages
        Weights storage weights = weeklyWeightPoints[currentWeek];
        weights.genesisWtPoints = _calcWeightPoints(weights.genesisWtPoints,gW,startCurrentWeek);
    }

    /// @dev Time weighted average of the token weightings
    function _calcWeightPoints(
        uint256 prevWeight,
        uint256 newWeight,
        uint256 startCurrentWeek
    ) 
        internal 
        view 
        returns(uint256) 
    {
        uint256 previousWeighting = prevWeight.mul(lastRewardTime.sub(startCurrentWeek));
        uint256 currentWeighting = newWeight.mul(block.timestamp.sub(lastRewardTime));
        return previousWeighting.add(currentWeighting)
                                .div(block.timestamp.sub(startCurrentWeek));
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256 c) {
        c = a >= b ? a : b;
    }
    
    /// @notice Normalised weightings of weights with point multiplier 
    function _getReturnWeights(
        uint256 _g,
    )   
        internal
        view
        returns (uint256)
    {
        uint256 eg = _g.mul(_getSqrtWeight(_g));

        return eg.mul(POINT_MULTIPLIER).mul(1e18).div(eg);
    }


    /// @notice Normalised weightings  
    function _getSqrtWeight(
        uint256 _a,
    )  
        internal
        view
        returns(
            uint256 wA
        )
    {
        return 1e18;
    }

    /* ========== Recover ERC20 ========== */

    /// @notice allows for the recovery of incorrect ERC20 tokens sent to contract
    function recoverERC20(
        address tokenAddress,
        uint256 tokenAmount
    )
        external
    {
        // Cannot recover the staking token or the rewards token
        require(
            accessControls.hasAdminRole(msg.sender),
            "Rewards.recoverERC20: Sender must be admin"
        );
        require(
            tokenAddress != address(rewardsToken),
            "Cannot withdraw the rewards token"
        );
        IERC20(tokenAddress).transfer(msg.sender, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }


    /* ========== Getters ========== */

    function getCurrentWeek()
        external
        view
        returns(uint256)
    {
        return diffDays(startTime, block.timestamp) / 7;
    }


    function getCurrentGenesisWtPoints()
        external
        view
        returns(uint256)
    {
        uint256 currentWeek = diffDays(startTime, block.timestamp) / 7;
        return weeklyWeightPoints[currentWeek].genesisWtPoints;
    }

    function getGenesisStakedEthTotal()
        public
        view
        returns(uint256)
    {
        return genesisStaking.stakedEthTotal();
    }

    function getGenesisDailyAPY()
        external
        view 
        returns (uint256) 
    {
        uint256 stakedEth = getGenesisStakedEthTotal();
        if ( stakedEth == 0 ) {
            return 0;
        }
        uint256 rewards = genesisRewards(block.timestamp - 60, block.timestamp);
        uint256 rewardsInEth = rewards.mul(getEthPerKEEP()).div(1e18);
        return rewardsInEth.mul(52560000).mul(1e18).div(stakedEth);
    } 

    function getKEEPPerEth()
        public 
        view 
        returns (uint256)
    {
        (uint256 wethReserve, uint256 tokenReserve) = getPairReserves();
        return UniswapV2Library.quote(1e18, wethReserve, tokenReserve);
    }

    function getEthPerKEEP()
        public
        view
        returns (uint256)
    {
        (uint256 wethReserve, uint256 tokenReserve) = getPairReserves();
        return UniswapV2Library.quote(1e18, tokenReserve, wethReserve);
    }

    function getPairReserves() internal view returns (uint256 wethReserves, uint256 tokenReserves) {
        (address token0,) = UniswapV2Library.sortTokens(address(lpStaking.WETH()), address(rewardsToken));
        (uint256 reserve0, uint reserve1,) = IUniswapV2Pair(lpStaking.lpToken()).getReserves();
        (wethReserves, tokenReserves) = token0 == address(rewardsToken) ? (reserve1, reserve0) : (reserve0, reserve1);
    }

}