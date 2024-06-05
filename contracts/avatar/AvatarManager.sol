pragma solidity >=0.8.4;

import "./IAvatar.sol";
import "../ethregistrar/StringUtils.sol";
import "../ethregistrar/IBaseRegistrar.sol";
import "../ethregistrar/ERC6551Proxy.sol";
import "../ethregistrar/IERC6551Registry.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

contract AvatarManager is ERC6551Proxy, Ownable2StepUpgradeable {
    using StringUtils for *;

    IBaseRegistrar public immutable base;
    uint256 public immutable numTokens;

    address[] public avatars;
    mapping(address => uint256) public avatarIndexes;
    mapping(uint256 => bool) public isClaimed;

    event AvatarAdded(address avatar, uint256 index);

    constructor(
        IBaseRegistrar _base,
        uint256 _numTokens,
        IERC6551Registry _registry,
        address _accountProxy,
        address _implementation,
        bytes32 _salt
    ) ERC6551Proxy(_registry, _accountProxy, _implementation, _salt) {
        base = _base;
        numTokens = _numTokens;

        _disableInitializers();
    }

    function initialize() external initializer {
        __Ownable2Step_init();
    }

    function _makeTokenId(string memory name) internal pure returns (uint256) {
        return uint256(keccak256(bytes(name)));
    }

    function _calcNumByName(
        string memory name
    ) internal view returns (uint256 num) {
        uint256 len = name.strlen();
        if (len == 3) {
            num = 3;
        } else if (len == 4) {
            num = 2;
        } else {
            num = 1;
        }
        uint256 nameExpires = base.nameExpires(_makeTokenId(name));
        uint256 numYear = (nameExpires - block.timestamp) / 365 days + 1;
        if (numYear >= 3) {
            num += 2;
        } else {
            num += 1;
        }
    }

    function addAvatar(address avatar) external onlyOwner {
        if (avatars.length > 0) {
            require(avatars[avatarIndexes[avatar]] != avatar, "already added");
        }

        avatars.push(avatar);
        uint256 index = avatars.length - 1;
        avatarIndexes[avatar] = index;
        emit AvatarAdded(avatar, index);
    }

    function mint(string memory name) external {
        uint256 tokenId = _makeTokenId(name);
        address account6551 = super._createAccount(address(base), tokenId);

        require(account6551 == msg.sender, "not 6551 account");
        require(!isClaimed[tokenId], "already claimed");
        isClaimed[tokenId] = true;

        uint256 len = avatars.length;
        uint256 num = _calcNumByName(name);
        uint256 seed = uint256(
            keccak256(abi.encodePacked(address(this), tokenId))
        );

        for (uint256 i; i < num; i++) {
            uint256 iAvatar = uint256(keccak256(abi.encodePacked(seed, i))) %
                len;
            uint256 iTokenId = uint256(
                keccak256(abi.encodePacked(seed, i, iAvatar))
            ) % numTokens;
            IAvatar(avatars[iAvatar]).mint(account6551, iTokenId, 1);
        }
    }
}
