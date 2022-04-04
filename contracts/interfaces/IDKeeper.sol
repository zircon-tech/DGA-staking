// SPDX-License-Identifier: GPLv2

pragma solidity 0.6.12;

/// @dev an interface to interact with the Genesis DEEP NFT that will 
interface IDKeeper {
    function contribution(address user) external view returns (uint256);
    function totalContributions() external view returns (uint256);
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}
