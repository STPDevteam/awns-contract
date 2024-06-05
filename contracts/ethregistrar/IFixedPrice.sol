//SPDX-License-Identifier: MIT
pragma solidity >=0.8.17 <0.9.0;

interface IFixedPrice {
    struct Price {
        uint256 oBase;
        uint256 oPremium;
        uint256 base;
        uint256 premium;
    }
    struct PriceParams {
        string name;
        bool premium;
        address booker;
        uint256 duration;
        uint256 discount;
        uint256 discountCount;
        string discountCode;
        address discountBinding;
        uint256 maxDeduct;
        uint256 minLimit;
        uint256 timestamp;
        bytes signature;
    }

    function verifyReferralReward(
        uint256 reward,
        string calldata referral,
        bytes calldata signature
    ) external view returns (bool);

    function price(
        uint256 expires,
        PriceParams calldata priceParams
    ) external view returns (Price calldata);
}
