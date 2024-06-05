//SPDX-License-Identifier: MIT
pragma solidity ~0.8.17;

import "./IERC6551Registry.sol";

interface IERC6551Account {
    function initialize(address _implementation) external;
}

contract ERC6551Proxy {
    IERC6551Registry public immutable registry;
    address public immutable accountProxy;
    address public immutable implementation;
    bytes32 public immutable salt;

    constructor(
        IERC6551Registry _registry,
        address _accountProxy,
        address _implementation,
        bytes32 _salt
    ) {
        registry = _registry;
        accountProxy = _accountProxy;
        implementation = _implementation;
        salt = _salt;
    }

    function _createAccount(
        address _token,
        uint256 _tokenId
    ) internal returns (address) {
        address account = registry.createAccount(
            accountProxy,
            salt,
            block.chainid,
            _token,
            _tokenId
        );
        try IERC6551Account(account).initialize(implementation) {} catch (
            bytes memory lowLevelData
        ) {
            require(bytes4(lowLevelData) == bytes4(0x0dc149f0));
        }

        return account;
    }
}
