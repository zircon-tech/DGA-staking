// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./ERC721/ERC721WithSameTokenURIForAllTokens.sol";
import "./AccessControls.sol";

/**
 * @title DKeeper Genesis NFT
 * @author ZirconTech
 * @dev To facilitate the genesis sale for the DGA platform
 */
contract DKeeper is ERC721WithSameTokenURIForAllTokens("DKeeper", "DKEEP") {
    using SafeMath for uint256;

    // @notice event emitted upon construction of this contract, used to bootstrap external indexers
    event DKeeperContractDeployed();

    // @notice event emitted when a contributor buys a Genesis NFT
    event GenesisPurchased(
        address indexed buyer,
        uint256 indexed tokenId,
        uint256 contribution
    );

    // @notice event emitted when a admin mints a Genesis NFT
    event AdminGenesisMinted(
        address indexed beneficiary,
        address indexed admin,
        uint256 indexed tokenId
    );

    // @notice event emitted when a contributors amount is increased
    event ContributionIncreased(
        address indexed buyer,
        uint256 contribution
    );

    // @notice event emitted when end date is changed
    event GenesisEndUpdated(
        uint256 genesisEndTimestamp,
        address indexed admin
    );

    // @notice event emitted when AccessControls is updated
    event AccessControlsUpdated(
        address indexed newAdress
    );

    // @notice responsible for enforcing admin access
    AccessControls public accessControls;

    // @notice all funds will be sent to this address pon purchase of a Genesis NFT
    address payable public fundsMultisig;

    // @notice start date for them the Genesis sale is open to the public, before this data no purchases can be made
    uint256 public genesisStartTimestamp;

    // @notice end date for them the Genesis sale is closed, no more purchased can be made after this point
    uint256 public genesisEndTimestamp;

    // @notice set after end time has been changed once, prevents further changes to end timestamp
    bool public genesisEndTimestampLocked;

    // @notice the minimum amount a buyer can contribute in a single go
    uint256 public constant MINIMUM_CONTRIBUTION_AMOUNT = 0.5 ether;

    // @notice the maximum accumulative amount a user can contribute to the genesis sale
    uint256 public constant MAXIMUM_CONTRIBUTION_AMOUNT = 2 ether;

    // @notice accumulative => contribution total
    mapping(address => uint256) public contribution;

    // @notice global accumulative contribution amount
    uint256 public totalContributions;

    // @notice max number of paid contributions to the genesis sale
    uint256 public constant MAX_GENESIS_CONTRIBUTION_TOKENS = 200;

    uint256 public totalAdminMints;

    constructor(
        AccessControls _accessControls,
        address payable _fundsMultisig,
        uint256 _genesisStartTimestamp,
        uint256 _genesisEndTimestamp,
        string memory _tokenURI
    ) public {
        accessControls = _accessControls;
        fundsMultisig = _fundsMultisig;
        genesisStartTimestamp = _genesisStartTimestamp;
        genesisEndTimestamp = _genesisEndTimestamp;
        tokenURI_ = _tokenURI;
        emit DKeeperContractDeployed();
    }

    /**
     * @dev Proxy method for facilitating a single point of entry to either buy or contribute additional value to the Genesis sale
     * @dev Cannot contribute less than MINIMUM_CONTRIBUTION_AMOUNT
     * @dev Cannot contribute accumulative more than than MAXIMUM_CONTRIBUTION_AMOUNT
     */
    function buyOrIncreaseContribution() external payable {
        if (contribution[_msgSender()] == 0) {
            buy();
        } else {
            increaseContribution();
        }
    }

    /**
     * @dev Facilitating the initial purchase of a Genesis NFT
     * @dev Cannot contribute less than MINIMUM_CONTRIBUTION_AMOUNT
     * @dev Cannot contribute accumulative more than than MAXIMUM_CONTRIBUTION_AMOUNT
     * @dev Reverts if already owns an genesis token
     * @dev Buyer receives a NFT on success
     * @dev All funds move to fundsMultisig
     */
    function buy() public payable {
        require(contribution[_msgSender()] == 0, "DKeeper.buy: You already own a genesis NFT");
        require(
            _getNow() >= genesisStartTimestamp && _getNow() <= genesisEndTimestamp,
            "DKeeper.buy: No genesis are available outside of the genesis window"
        );

        uint256 _contributionAmount = msg.value;
        require(
            _contributionAmount >= MINIMUM_CONTRIBUTION_AMOUNT,
            "DKeeper.buy: Contribution does not meet minimum requirement"
        );

        require(
            _contributionAmount <= MAXIMUM_CONTRIBUTION_AMOUNT,
            "DKeeper.buy: You cannot exceed the maximum contribution amount"
        );

        require(remainingGenesisTokens() > 0, "DKeeper.buy: Total number of genesis token holders reached");

        contribution[_msgSender()] = _contributionAmount;
        totalContributions = totalContributions.add(_contributionAmount);

        (bool fundsTransferSuccess,) = fundsMultisig.call{value : _contributionAmount}("");
        require(fundsTransferSuccess, "DKeeper.buy: Unable to send contribution to funds multisig");

        uint256 tokenId = totalSupply().add(1);
        _safeMint(_msgSender(), tokenId);

        emit GenesisPurchased(_msgSender(), tokenId, _contributionAmount);
    }

    /**
     * @dev Facilitates an owner to increase there contribution
     * @dev Cannot contribute less than MINIMUM_CONTRIBUTION_AMOUNT
     * @dev Cannot contribute accumulative more than than MAXIMUM_CONTRIBUTION_AMOUNT
     * @dev All funds move to fundsMultisig
     * @dev Reverts if caller does not already owns an genesis token
     */
    function increaseContribution() public payable {
        require(
            _getNow() >= genesisStartTimestamp && _getNow() <= genesisEndTimestamp,
            "DKeeper.increaseContribution: No increases are possible outside of the genesis window"
        );

        require(
            contribution[_msgSender()] > 0,
            "DKeeper.increaseContribution: You do not own a genesis NFT"
        );

        uint256 _amountToIncrease = msg.value;
        contribution[_msgSender()] = contribution[_msgSender()].add(_amountToIncrease);

        require(
            contribution[_msgSender()] <= MAXIMUM_CONTRIBUTION_AMOUNT,
            "DKeeper.increaseContribution: You cannot exceed the maximum contribution amount"
        );

        totalContributions = totalContributions.add(_amountToIncrease);

        (bool fundsTransferSuccess,) = fundsMultisig.call{value : _amountToIncrease}("");
        require(
            fundsTransferSuccess,
            "DKeeper.increaseContribution: Unable to send contribution to funds multisig"
        );

        emit ContributionIncreased(_msgSender(), _amountToIncrease);
    }

    // Admin

    /**
     * @dev Allows a whitelisted admin to mint a token and issue it to a beneficiary
     * @dev One token per holder
     * @dev All holders contribution as set o zero on creation
     */
    function adminBuy(address _beneficiary) external {
        require(
            accessControls.hasAdminRole(_msgSender()),
            "DKeeper.adminBuy: Sender must be admin"
        );
        require(_beneficiary != address(0), "DKeeper.adminBuy: Beneficiary cannot be ZERO");
        require(balanceOf(_beneficiary) == 0, "DKeeper.adminBuy: Beneficiary already owns a genesis NFT");

        uint256 tokenId = totalSupply().add(1);
        _safeMint(_beneficiary, tokenId);

        // Increase admin mint counts
        totalAdminMints = totalAdminMints.add(1);

        emit AdminGenesisMinted(_beneficiary, _msgSender(), tokenId);
    }

    /**
     * @dev Allows a whitelisted admin to update the end date of the genesis
     */
    function updateGenesisEnd(uint256 _end) external {
        require(
            accessControls.hasAdminRole(_msgSender()),
            "DKeeper.updateGenesisEnd: Sender must be admin"
        );
        // If already passed, dont allow opening again
        require(genesisEndTimestamp > _getNow(), "DKeeper.updateGenesisEnd: End time already passed");

        // Only allow setting this once
        require(!genesisEndTimestampLocked, "DKeeper.updateGenesisEnd: End time locked");

        genesisEndTimestamp = _end;

        // Lock future end time modifications
        genesisEndTimestampLocked = true;

        emit GenesisEndUpdated(genesisEndTimestamp, _msgSender());
    }

    /**
     * @dev Allows a whitelisted admin to update the start date of the genesis
     */
    function updateAccessControls(AccessControls _accessControls) external {
        require(
            accessControls.hasAdminRole(_msgSender()),
            "DKeeper.updateAccessControls: Sender must be admin"
        );
        require(address(_accessControls) != address(0), "DKeeper.updateAccessControls: Zero Address");
        accessControls = _accessControls;

        emit AccessControlsUpdated(address(_accessControls));
    }

    /**
    * @dev Returns total remaining number of tokens available in the Genesis sale
    */
    function remainingGenesisTokens() public view returns (uint256) {
        return _getMaxGenesisContributionTokens() - (totalSupply() - totalAdminMints);
    }

    // Internal

    function _getNow() internal virtual view returns (uint256) {
        return block.timestamp;
    }

    function _getMaxGenesisContributionTokens() internal virtual view returns (uint256) {
        return MAX_GENESIS_CONTRIBUTION_TOKENS;
    }

    /**
     * @dev Before token transfer hook to enforce that no token can be moved to another address until the genesis sale has ended
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override {
        if (from != address(0) && _getNow() <= genesisEndTimestamp) {
            revert("DKeeper._beforeTokenTransfer: Transfers are currently locked at this time");
        }
    }
}