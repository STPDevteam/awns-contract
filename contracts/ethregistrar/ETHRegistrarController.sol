//SPDX-License-Identifier: MIT
pragma solidity ~0.8.17;

import {BaseRegistrarImplementation} from "./BaseRegistrarImplementation.sol";
import {StringUtils} from "./StringUtils.sol";
import {Resolver} from "../resolvers/Resolver.sol";
import {ENS} from "../registry/ENS.sol";
import {ReverseRegistrar} from "../reverseRegistrar/ReverseRegistrar.sol";
import {ReverseClaimerUpgradeable} from "../reverseRegistrar/ReverseClaimerUpgradeable.sol";
import {IETHRegistrarController, IFixedPrice} from "./IETHRegistrarController.sol";

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {INameWrapper} from "../wrapper/INameWrapper.sol";
import "./ERC6551Proxy.sol";
import "./IERC6551Registry.sol";

error CommitmentTooNew(bytes32 commitment);
error CommitmentTooOld(bytes32 commitment);
error NameNotAvailable(string name);
error DurationTooShort(uint256 duration);
error ResolverRequiredWhenDataSupplied();
error InsufficientValue();
error Unauthorised(bytes32 node);
error ExceedDiscountCodeCount();

/**
 * @dev A registrar controller for registering and renewing names at fixed cost.
 */
contract ETHRegistrarController is
    Ownable2StepUpgradeable,
    IETHRegistrarController,
    IERC165,
    ReverseClaimerUpgradeable,
    ERC6551Proxy
{
    using StringUtils for *;
    using Address for address;

    uint256 public constant MIN_REGISTRATION_DURATION = 90 days;
    bytes32 private constant ETH_NODE =
        0x767f7ae3892e8f65e301186af62302d724c247381454284930e6b6df3ce477b1;
    uint64 private constant MAX_EXPIRY = type(uint64).max;
    BaseRegistrarImplementation immutable base;
    IFixedPrice public immutable prices;
    ReverseRegistrar public immutable reverseRegistrar;
    INameWrapper public immutable nameWrapper;

    uint256 public referralRewardRate;
    uint256 public totalReferralRewards;
    mapping(string => uint256) public referralRewards;
    mapping(uint256 => uint32) public discountsUsedCounter;
    address public beneficiary;
    bool public registrable;

    event NameRegistered(
        string name,
        bytes32 indexed label,
        address indexed owner,
        uint256 baseCost,
        uint256 premium,
        uint256 expires
    );
    event NameRenewed(
        string name,
        bytes32 indexed label,
        uint256 cost,
        uint256 expires
    );
    event DiscountUsed(string discountCode, uint256 discount);
    event Referral(string referral, string registrant, uint256 referralReward);

    constructor(
        BaseRegistrarImplementation _base,
        IFixedPrice _prices,
        ReverseRegistrar _reverseRegistrar,
        INameWrapper _nameWrapper,
        IERC6551Registry _registry,
        address _accountProxy,
        address _implementation,
        bytes32 _salt
    ) ERC6551Proxy(_registry, _accountProxy, _implementation, _salt) {
        base = _base;
        prices = _prices;
        reverseRegistrar = _reverseRegistrar;
        nameWrapper = _nameWrapper;
    }

    function initialize(
        ENS _ens,
        uint256 _referralRewardRate,
        address _beneficiary
    ) external initializer {
        referralRewardRate = _referralRewardRate;
        beneficiary = _beneficiary;

        Ownable2StepUpgradeable.__Ownable2Step_init();
        ReverseClaimerUpgradeable.__ReverseClaimer_initialize(_ens, msg.sender);
    }

    function rentPrice(
        IFixedPrice.PriceParams calldata priceParams
    ) public view override returns (IFixedPrice.Price memory price) {
        bytes32 label = keccak256(bytes(priceParams.name));
        price = prices.price(base.nameExpires(uint256(label)), priceParams);
    }

    function valid(string memory name) public pure returns (bool) {
        return name.strlen() >= 3;
    }

    function available(string memory name) public view override returns (bool) {
        bytes32 label = keccak256(bytes(name));
        return valid(name) && base.available(uint256(label));
    }

    function discountsUsed(string memory code) public view returns (uint32) {
        return discountsUsedCounter[uint256(keccak256(bytes(code)))];
    }

    function register(
        address owner,
        address resolver,
        bytes[] calldata data,
        bool reverseRecord,
        uint16 ownerControlledFuses,
        string calldata referral,
        IFixedPrice.PriceParams calldata priceParams
    ) public payable override {
        require(registrable, "!registrable");

        IFixedPrice.Price memory price = rentPrice(priceParams);
        if (msg.value < price.base + price.premium) {
            revert InsufficientValue();
        }
        if (priceParams.duration < MIN_REGISTRATION_DURATION) {
            revert DurationTooShort(priceParams.duration);
        }
        if (priceParams.booker != address(0)) {
            require(owner == priceParams.booker, "!whitelist");
        }
        if (
            priceParams.discountBinding != address(0) ||
            priceParams.discount == 0
        ) {
            require(owner == priceParams.discountBinding, "!binding");
        }
        _consumeDiscountCode(priceParams);

        uint256 expires = nameWrapper.registerAndWrapETH2LD(
            priceParams.name,
            owner,
            priceParams.duration,
            resolver,
            ownerControlledFuses
        );
        nameWrapper.unwrapETH2LDByController(
            keccak256(bytes(priceParams.name))
        );
        super._createAccount(address(base), _makeTokenId(priceParams.name));

        if (data.length > 0) {
            _setRecords(resolver, keccak256(bytes(priceParams.name)), data);
        }

        if (reverseRecord) {
            _setReverseRecord(priceParams.name, resolver, msg.sender);
        }

        emit NameRegistered(
            priceParams.name,
            keccak256(bytes(priceParams.name)),
            owner,
            price.base,
            price.premium,
            expires
        );

        uint256 tvalue = price.base + price.premium;
        uint256 rvalue = (tvalue * referralRewardRate) / 1 ether;
        totalReferralRewards += rvalue;
        emit Referral(referral, priceParams.name, rvalue);

        if (msg.value > tvalue) {
            payable(msg.sender).transfer(msg.value - tvalue);
        }
        payable(beneficiary).transfer(tvalue - rvalue);
    }

    function renew(
        IFixedPrice.PriceParams calldata priceParams
    ) external payable override {
        bytes32 labelhash = keccak256(bytes(priceParams.name));
        uint256 tokenId = uint256(labelhash);
        IFixedPrice.Price memory price = rentPrice(priceParams);
        if (msg.value < price.base) {
            revert InsufficientValue();
        }
        _consumeDiscountCode(priceParams);

        uint256 expires = nameWrapper.renew(tokenId, priceParams.duration);

        if (msg.value > price.base) {
            payable(msg.sender).transfer(msg.value - price.base);
        }
        payable(beneficiary).transfer(price.base + price.premium);

        emit NameRenewed(priceParams.name, labelhash, msg.value, expires);
    }

    function setRewardRate(uint256 _referralRewardRate) public onlyOwner {
        referralRewardRate = _referralRewardRate;
    }

    function setBeneficiary(address _beneficiary) public onlyOwner {
        beneficiary = _beneficiary;
    }

    function setRegistrable(bool _registrable) public onlyOwner {
        registrable = _registrable;
    }

    function claimReferralReward(
        string calldata name,
        uint256 referralReward,
        bytes calldata signature
    ) public {
        require(base.ownerOf(_makeTokenId(name)) == msg.sender);
        require(prices.verifyReferralReward(referralReward, name, signature));

        uint256 claimable = referralReward - referralRewards[name];
        totalReferralRewards -= claimable;
        referralRewards[name] = referralReward;
        payable(msg.sender).transfer(claimable);
    }

    function supportsInterface(
        bytes4 interfaceID
    ) external pure returns (bool) {
        return
            interfaceID == type(IERC165).interfaceId ||
            interfaceID == type(IETHRegistrarController).interfaceId;
    }

    /* Internal functions */
    function _consumeDiscountCode(
        IFixedPrice.PriceParams calldata priceParams
    ) internal {
        uint256 dCode = uint256(keccak256(bytes(priceParams.discountCode)));
        uint32 used = discountsUsedCounter[dCode] + 1;
        if (
            priceParams.discount < 1 ether && used > priceParams.discountCount
        ) {
            revert ExceedDiscountCodeCount();
        }

        discountsUsedCounter[dCode] = used;
        emit DiscountUsed(priceParams.discountCode, priceParams.discount);
    }

    function _setRecords(
        address resolverAddress,
        bytes32 label,
        bytes[] calldata data
    ) internal {
        // use hardcoded .eth namehash
        bytes32 nodehash = keccak256(abi.encodePacked(ETH_NODE, label));
        Resolver resolver = Resolver(resolverAddress);
        resolver.multicallWithNodeCheck(nodehash, data);
    }

    function _setReverseRecord(
        string memory name,
        address resolver,
        address owner
    ) internal {
        reverseRegistrar.setNameForAddr(
            msg.sender,
            owner,
            resolver,
            string.concat(name, ".aw")
        );
    }

    function _makeTokenId(string memory _name) internal pure returns (uint256) {
        return uint256(keccak256(bytes(_name)));
    }
}
