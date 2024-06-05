pragma solidity ^0.8.0;

interface IAvatar {
    function mint(address to, uint256 tokenId, uint256 amount) external;

    function addAvatar(address avatar) external;
}
