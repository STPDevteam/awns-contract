//SPDX-License-Identifier: MIT
pragma solidity ~0.8.17;

import "./IFixedPrice.sol";

interface IETHRegistrarController {
    function rentPrice(
        IFixedPrice.PriceParams calldata priceParams
    ) external view returns (IFixedPrice.Price memory);

    function available(string memory) external returns (bool);

    function register(
        address,
        address,
        bytes[] calldata,
        bool,
        uint16,
        string calldata,
        IFixedPrice.PriceParams calldata
    ) external payable;

    function renew(
        IFixedPrice.PriceParams calldata priceParams
    ) external payable;
}
