pragma solidity >=0.8.4;

import "../ethregistrar/IBaseRegistrar.sol";
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";

contract Avatar is Ownable2StepUpgradeable, ERC1155Upgradeable {
    using StringsUpgradeable for uint256;

    address public immutable manager;
    string public name;
    string public symbol;

    constructor(address _manager) {
        manager = _manager;

        _disableInitializers();
    }

    function initialize(
        string memory _uri,
        string memory _name,
        string memory _symbol
    ) external initializer {
        __Ownable2Step_init();
        __ERC1155_init(_uri);
        name = _name;
        symbol = _symbol;
    }

    function setURI(string memory _url) external onlyOwner {
        super._setURI(_url);
    }

    function uri(
        uint256 _tokenId
    ) public view virtual override returns (string memory) {
        string memory baseURI = super.uri(_tokenId);
        return
            bytes(baseURI).length > 0
                ? string(abi.encodePacked(baseURI, _tokenId.toString()))
                : "";
    }

    function mint(address to, uint256 tokenId, uint256 amount) external {
        require(msg.sender == manager, "not approved");
        super._mint(to, tokenId, amount, "");
    }
}
