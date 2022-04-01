// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../DKeeper.sol";

contract DKeeperMock is DKeeper {
    uint256 public nowOverride;
    uint256 public maxGenesisContributionTokensOverride;

    constructor(
        AccessControls _accessControls,
        address payable _fundsMultisig,
        uint256 _genesisStart,
        uint256 _genesisEnd,
        string memory _tokenURI
    )
    public DKeeper(_accessControls, _fundsMultisig, _genesisStart, _genesisEnd, _tokenURI) {}

    function addContribution(uint256 _contributionAmount) external {
        contribution[_msgSender()] = _contributionAmount;
        totalContributions = totalContributions.add(_contributionAmount);
    }

    function setNowOverride(uint256 _now) external {
        nowOverride = _now;
    }

    function setMaxGenesisContributionTokensOverride(uint256 _maxGenesisContributionTokensOverride) external {
        maxGenesisContributionTokensOverride = _maxGenesisContributionTokensOverride;
    }

    function _getNow() internal override view returns (uint256) {
        return nowOverride;
    }

    function _getMaxGenesisContributionTokens() internal override view returns (uint256) {
        return maxGenesisContributionTokensOverride;
    }
}
