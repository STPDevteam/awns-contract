//SPDX-License-Identifier: MIT
pragma solidity ~0.8.17;

import "./IFixedPrice.sol";
import "./StringUtils.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract FixedPrice is IFixedPrice {
    using StringUtils for *;

    address public immutable signer;
    // Rent in base price units by length
    uint256 public immutable price3Letter;
    uint256 public immutable price4Letter;
    uint256 public immutable price5Letter;
    uint256 public immutable pricePremium;

    error UnExpectedLetterCount();
    error UnExpectedSignature();

    constructor(address _signer, uint256[] memory _rentPrices) {
        signer = _signer;

        price3Letter = _rentPrices[0];
        price4Letter = _rentPrices[1];
        price5Letter = _rentPrices[2];
        pricePremium = _rentPrices[3];
    }

    function verifyReferralReward(
        uint256 reward,
        string calldata referral,
        bytes calldata signature
    ) external view returns (bool) {
        bytes32 h = ECDSA.toEthSignedMessageHash(
            keccak256(abi.encodePacked(reward, bytes(referral)))
        );

        return ECDSA.recover(h, signature) == signer;
    }

    function price(
        uint256 expires,
        PriceParams memory priceParams
    ) external view override returns (IFixedPrice.Price memory) {
        uint256 _price;
        uint256 _oPrice;
        bytes32 h = ECDSA.toEthSignedMessageHash(
            keccak256(
                abi.encodePacked(
                    priceParams.timestamp,
                    priceParams.discount,
                    priceParams.discountCount,
                    bytes(priceParams.discountCode),
                    priceParams.discountBinding,
                    priceParams.maxDeduct,
                    priceParams.minLimit,
                    bytes(priceParams.name),
                    priceParams.premium,
                    priceParams.booker
                )
            )
        );
        if (
            block.timestamp < priceParams.timestamp + 1 days &&
            priceParams.signature.length == 65 &&
            ECDSA.recover(h, priceParams.signature) == signer
        ) {
            if (priceParams.premium) {
                _oPrice = pricePremium;
            } else {
                uint256 len = priceParams.name.strlen();

                if (len >= 5) {
                    _oPrice = price5Letter;
                } else if (len == 4) {
                    _oPrice = price4Letter;
                } else if (len == 3) {
                    _oPrice = price3Letter;
                } else {
                    revert UnExpectedLetterCount();
                }
            }
        } else {
            revert UnExpectedSignature();
        }

        _oPrice = (_oPrice * priceParams.duration) / 365 days;
        uint deduct;
        if (_oPrice > priceParams.minLimit) {
            deduct = _oPrice - ((_oPrice * priceParams.discount) / 1 ether);
            if (priceParams.maxDeduct > 0 && deduct > priceParams.maxDeduct) {
                deduct = priceParams.maxDeduct;
            }
        }
        _price = _oPrice - deduct;

        return
            IFixedPrice.Price({
                oBase: _oPrice,
                oPremium: 0,
                base: _price,
                premium: 0
            });
    }
}
