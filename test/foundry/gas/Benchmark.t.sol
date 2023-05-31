// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {
    OrderType,
    BasicOrderType,
    ItemType
} from "seaport-types/src/lib/ConsiderationEnums.sol";

import {
    ConsiderationInterface
} from "seaport-types/src/interfaces/ConsiderationInterface.sol";

import {
    AdditionalRecipient,
    Order,
    OrderComponents,
    BasicOrderParameters,
    OfferItem,
    OrderParameters,
    ConsiderationItem,
    AdvancedOrder,
    FulfillmentComponent,
    CriteriaResolver
} from "seaport-types/src/lib/ConsiderationStructs.sol";

import { BaseOrderTest } from "../utils/BaseOrderTest.sol";

import {
    InvalidEthRecipient
} from "../../../contracts/test/InvalidEthRecipient.sol";

import { TestERC721 } from "../../../contracts/test/TestERC721.sol";

import { TestERC1155 } from "../../../contracts/test/TestERC1155.sol";

import { TestERC20 } from "../../../contracts/test/TestERC20.sol";

import { ArithmeticUtil } from "../utils/ArithmeticUtil.sol";

import {
    ConsiderationEventsAndErrors
} from "seaport-types/src/interfaces/ConsiderationEventsAndErrors.sol";

import { Seaport } from "seaport-core/src/Seaport.sol";

contract Benchmark is BaseOrderTest, ConsiderationEventsAndErrors {
    using ArithmeticUtil for uint128;

    uint256 badIdentifier;
    address badToken;
    BasicOrderParameters basicOrderParameters;
    address payable invalidRecipientAddress;
    FuzzInputsCommon empty;
    uint256 internal abePk = 0xabe;
    address payable internal abe = payable(vm.addr(abePk));

    struct FuzzInputsCommon {
        address zone;
        uint256 tokenId;
        uint128 paymentAmount;
        bytes32 zoneHash;
        uint256 salt;
        bool useConduit;
    }

    struct FuzzInputsCommonFulfillOrder {
        address zone;
        uint128 id;
        bytes32 zoneHash;
        uint256 salt;
        uint128[3] paymentAmts;
        bool useConduit;
        uint120 startAmount;
        uint120 endAmount;
        uint16 warpAmount;
    }

    struct Context {
        ConsiderationInterface consideration;
        FuzzInputsCommon args;
        uint128 tokenAmount;
    }

    modifier validateInputs(Context memory context) {
        vm.assume(context.args.paymentAmount > 0);
        _;
    }

    modifier validateInputsWithAmount(Context memory context) {
        vm.assume(context.args.paymentAmount > 0);
        vm.assume(context.args.tokenId > 0);
        vm.assume(context.tokenAmount > 0);
        _;
    }

    function test(
        function(Context memory) external fn,
        Context memory context
    ) internal {
        try fn(context) {} catch (bytes memory reason) {
            assertPass(reason);
        }
    }

    Seaport seaport;

    function setUp() public virtual override {
        super.setUp();

        seaport = new Seaport(address(conduitController));

        conduitController.updateChannel(
            address(conduit),
            address(seaport),
            true
        );

        vm.startPrank(alice);
        test721_1.setApprovalForAll(address(seaport), true);
        token1.approve(address(seaport), uint128(MAX_INT));
        vm.stopPrank();

        vm.startPrank(bob);
        test721_1.setApprovalForAll(address(seaport), true);
        token1.approve(address(seaport), uint128(MAX_INT));
        vm.stopPrank();

        allocateTokensAndApprovals(abe, uint128(MAX_INT));
    }

    // Basic Eth to 721
    function test_benchmarkBuySingleListingNoFeesNoConduit(FuzzInputsCommon memory inputs) public {
        vm.assume(inputs.useConduit == false);

        uint128 paymentAmount = 100 ether;

        for (uint256 tokenId = 1; tokenId <= 100; tokenId++) {
            FuzzInputsCommon memory remappedInputs = inputs;
            remappedInputs.paymentAmount = paymentAmount;
            remappedInputs.tokenId = tokenId;

            addErc721OfferItem(remappedInputs.tokenId);
            addEthConsiderationItem(alice, remappedInputs.paymentAmount);
            _configureBasicOrderParametersEthTo721(remappedInputs);
    
            test721_1.mint(alice, remappedInputs.tokenId);
    
            configureOrderComponents(
                remappedInputs.zone,
                remappedInputs.zoneHash,
                remappedInputs.salt,
                remappedInputs.useConduit ? conduitKeyOne : bytes32(0)
            );
            uint256 counter = seaport.getCounter(alice);
            baseOrderComponents.counter = counter;
            bytes32 orderHash = seaport.getOrderHash(
                baseOrderComponents
            );
            bytes memory signature = signOrder(
                seaport,
                alicePk,
                orderHash
            );
    
            basicOrderParameters.signature = signature;
    
            vm.prank(bob);
            seaport.fulfillBasicOrder{
                value: remappedInputs.paymentAmount
            }(basicOrderParameters);

            delete offerItems;
            delete considerationItems;
            delete basicOrderParameters;
            delete baseOrderComponents;
        }
    }

    function test_benchmarkBuySingleListingNoFeesUseConduit(FuzzInputsCommon memory inputs) public {
        vm.assume(inputs.useConduit == true);

        uint128 paymentAmount = 100 ether;

        for (uint256 tokenId = 1; tokenId <= 100; tokenId++) {
            FuzzInputsCommon memory remappedInputs = inputs;
            remappedInputs.paymentAmount = paymentAmount;
            remappedInputs.tokenId = tokenId;

            addErc721OfferItem(remappedInputs.tokenId);
            addEthConsiderationItem(alice, remappedInputs.paymentAmount);
            _configureBasicOrderParametersEthTo721(remappedInputs);
    
            test721_1.mint(alice, remappedInputs.tokenId);
    
            configureOrderComponents(
                remappedInputs.zone,
                remappedInputs.zoneHash,
                remappedInputs.salt,
                remappedInputs.useConduit ? conduitKeyOne : bytes32(0)
            );
            uint256 counter = seaport.getCounter(alice);
            baseOrderComponents.counter = counter;
            bytes32 orderHash = seaport.getOrderHash(
                baseOrderComponents
            );
            bytes memory signature = signOrder(
                seaport,
                alicePk,
                orderHash
            );
    
            basicOrderParameters.signature = signature;
    
            vm.prank(bob);
            seaport.fulfillBasicOrder{
                value: remappedInputs.paymentAmount
            }(basicOrderParameters);

            delete offerItems;
            delete considerationItems;
            delete basicOrderParameters;
            delete baseOrderComponents;
        }
    }

    // Basic Eth to 721 with one additional recipient
    function test_benchmarkBuySingleListingMarketplaceFeesNoConduit(FuzzInputsCommon memory inputs) public {
        vm.assume(inputs.useConduit == false);

        uint128 paymentAmount = 95 ether;
        uint128 marketplaceFee = 5 ether;

        for (uint256 tokenId = 1; tokenId <= 100; tokenId++) {
            FuzzInputsCommon memory remappedInputs = inputs;
            remappedInputs.paymentAmount = paymentAmount;
            remappedInputs.tokenId = tokenId;

            addErc721OfferItem(remappedInputs.tokenId);
            addEthConsiderationItem(alice, remappedInputs.paymentAmount);

            AdditionalRecipient[]
            storage _additionalRecipients = additionalRecipients;

            _additionalRecipients.push(
                AdditionalRecipient({
                    recipient: cal,
                    amount: marketplaceFee
                })
            );
            addEthConsiderationItem(cal, marketplaceFee);

            _configureBasicOrderParametersEthTo721(remappedInputs);
            basicOrderParameters.additionalRecipients = _additionalRecipients;
            basicOrderParameters.considerationAmount = remappedInputs.paymentAmount;
            basicOrderParameters.totalOriginalAdditionalRecipients = 1;
            basicOrderParameters.fulfillerConduitKey = inputs.useConduit ? conduitKeyOne : bytes32(0);

            test721_1.mint(alice, remappedInputs.tokenId);

            configureOrderComponents(
            remappedInputs.zone,
            remappedInputs.zoneHash,
            remappedInputs.salt,
            remappedInputs.useConduit ? conduitKeyOne : bytes32(0)
            );
            uint256 counter = seaport.getCounter(alice);
            baseOrderComponents.counter = counter;
    
            bytes32 orderHash = seaport.getOrderHash(
                baseOrderComponents
            );

            bytes memory signature = signOrder(
                seaport,
                alicePk,
                orderHash
            );
    
            basicOrderParameters.signature = signature;

            vm.prank(bob);
            seaport.fulfillBasicOrder{value: (remappedInputs.paymentAmount + marketplaceFee)}(basicOrderParameters);

            delete offerItems;
            delete considerationItems;
            delete basicOrderParameters;
            delete baseOrderComponents;
            delete additionalRecipients;
        }
    }

    function test_benchmarkBuySingleListingMarketplaceFeesUseConduit(FuzzInputsCommon memory inputs) public {
        vm.assume(inputs.useConduit == true);

        uint128 paymentAmount = 95 ether;
        uint128 marketplaceFee = 5 ether;

        for (uint256 tokenId = 1; tokenId <= 100; tokenId++) {
            FuzzInputsCommon memory remappedInputs = inputs;
            remappedInputs.paymentAmount = paymentAmount;
            remappedInputs.tokenId = tokenId;

            addErc721OfferItem(remappedInputs.tokenId);
            addEthConsiderationItem(alice, remappedInputs.paymentAmount);

            AdditionalRecipient[]
            storage _additionalRecipients = additionalRecipients;

            _additionalRecipients.push(
                AdditionalRecipient({
                    recipient: cal,
                    amount: marketplaceFee
                })
            );
            addEthConsiderationItem(cal, marketplaceFee);

            _configureBasicOrderParametersEthTo721(remappedInputs);
            basicOrderParameters.additionalRecipients = _additionalRecipients;
            basicOrderParameters.considerationAmount = remappedInputs.paymentAmount;
            basicOrderParameters.totalOriginalAdditionalRecipients = 1;
            basicOrderParameters.fulfillerConduitKey = inputs.useConduit ? conduitKeyOne : bytes32(0);

            test721_1.mint(alice, remappedInputs.tokenId);

            configureOrderComponents(
            remappedInputs.zone,
            remappedInputs.zoneHash,
            remappedInputs.salt,
            remappedInputs.useConduit ? conduitKeyOne : bytes32(0)
            );
            uint256 counter = seaport.getCounter(alice);
            baseOrderComponents.counter = counter;
    
            bytes32 orderHash = seaport.getOrderHash(
                baseOrderComponents
            );

            bytes memory signature = signOrder(
                seaport,
                alicePk,
                orderHash
            );
    
            basicOrderParameters.signature = signature;

            vm.prank(bob);
            seaport.fulfillBasicOrder{value: (remappedInputs.paymentAmount + marketplaceFee)}(basicOrderParameters);

            delete offerItems;
            delete considerationItems;
            delete basicOrderParameters;
            delete baseOrderComponents;
            delete additionalRecipients;
        }
    }

    function test_benchmarkBuySingleListingMarketplaceAndRoyaltyFeesNoConduit(FuzzInputsCommon memory inputs) public {
        vm.assume(inputs.useConduit == false);

        uint128 paymentAmount = 85 ether;
        uint128 marketplaceFee = 5 ether;
        uint128 royaltyFee = 10 ether;

        for (uint256 tokenId = 1; tokenId <= 100; tokenId++) {
            FuzzInputsCommon memory remappedInputs = inputs;
            remappedInputs.paymentAmount = paymentAmount;
            remappedInputs.tokenId = tokenId;

            addErc721OfferItem(remappedInputs.tokenId);
            addEthConsiderationItem(alice, remappedInputs.paymentAmount);

            AdditionalRecipient[]
            storage _additionalRecipients = additionalRecipients;

            _additionalRecipients.push(
                AdditionalRecipient({
                    recipient: cal,
                    amount: marketplaceFee
                })
            );
            addEthConsiderationItem(cal, marketplaceFee);

            _additionalRecipients.push(
                AdditionalRecipient({
                    recipient: abe,
                    amount: royaltyFee
                })
            );
            addEthConsiderationItem(abe, royaltyFee);

            _configureBasicOrderParametersEthTo721(remappedInputs);
            basicOrderParameters.additionalRecipients = _additionalRecipients;
            basicOrderParameters.considerationAmount = remappedInputs.paymentAmount;
            basicOrderParameters.totalOriginalAdditionalRecipients = 2;
            basicOrderParameters.fulfillerConduitKey = inputs.useConduit ? conduitKeyOne : bytes32(0);

            test721_1.mint(alice, remappedInputs.tokenId);

            configureOrderComponents(
            remappedInputs.zone,
            remappedInputs.zoneHash,
            remappedInputs.salt,
            remappedInputs.useConduit ? conduitKeyOne : bytes32(0)
            );
            uint256 counter = seaport.getCounter(alice);
            baseOrderComponents.counter = counter;
    
            bytes32 orderHash = seaport.getOrderHash(
                baseOrderComponents
            );

            bytes memory signature = signOrder(
                seaport,
                alicePk,
                orderHash
            );
    
            basicOrderParameters.signature = signature;

            vm.prank(bob);
            seaport.fulfillBasicOrder{value: (remappedInputs.paymentAmount + marketplaceFee + royaltyFee)}(basicOrderParameters);

            delete offerItems;
            delete considerationItems;
            delete basicOrderParameters;
            delete baseOrderComponents;
            delete additionalRecipients;
        }
    }

    // Basic Eth to 721 with two additional recipients
    function test_benchmarkBuySingleListingMarketplaceAndRoyaltyFeesUseConduit(FuzzInputsCommon memory inputs) public {
        vm.assume(inputs.useConduit == true);

        uint128 paymentAmount = 85 ether;
        uint128 marketplaceFee = 5 ether;
        uint128 royaltyFee = 10 ether;

        for (uint256 tokenId = 1; tokenId <= 100; tokenId++) {
            FuzzInputsCommon memory remappedInputs = inputs;
            remappedInputs.paymentAmount = paymentAmount;
            remappedInputs.tokenId = tokenId;

            addErc721OfferItem(remappedInputs.tokenId);
            addEthConsiderationItem(alice, remappedInputs.paymentAmount);

            AdditionalRecipient[]
            storage _additionalRecipients = additionalRecipients;

            _additionalRecipients.push(
                AdditionalRecipient({
                    recipient: cal,
                    amount: marketplaceFee
                })
            );
            addEthConsiderationItem(cal, marketplaceFee);

            _additionalRecipients.push(
                AdditionalRecipient({
                    recipient: abe,
                    amount: royaltyFee
                })
            );
            addEthConsiderationItem(abe, royaltyFee);

            _configureBasicOrderParametersEthTo721(remappedInputs);
            basicOrderParameters.additionalRecipients = _additionalRecipients;
            basicOrderParameters.considerationAmount = remappedInputs.paymentAmount;
            basicOrderParameters.totalOriginalAdditionalRecipients = 2;
            basicOrderParameters.fulfillerConduitKey = inputs.useConduit ? conduitKeyOne : bytes32(0);

            test721_1.mint(alice, remappedInputs.tokenId);

            configureOrderComponents(
            remappedInputs.zone,
            remappedInputs.zoneHash,
            remappedInputs.salt,
            remappedInputs.useConduit ? conduitKeyOne : bytes32(0)
            );
            uint256 counter = seaport.getCounter(alice);
            baseOrderComponents.counter = counter;
    
            bytes32 orderHash = seaport.getOrderHash(
                baseOrderComponents
            );

            bytes memory signature = signOrder(
                seaport,
                alicePk,
                orderHash
            );
    
            basicOrderParameters.signature = signature;

            vm.prank(bob);
            seaport.fulfillBasicOrder{value: (remappedInputs.paymentAmount + marketplaceFee + royaltyFee)}(basicOrderParameters);

            delete offerItems;
            delete considerationItems;
            delete basicOrderParameters;
            delete baseOrderComponents;
            delete additionalRecipients;
        }
    }

    // Bundled Listing No Fees, Native Eth Payment, No Conduit
    function test_benchmarkBuyBundledListingNoFeesNoConduit(FuzzInputsCommonFulfillOrder memory inputs) public {
        vm.assume(inputs.useConduit == false);

        bytes32 conduitKey = inputs.useConduit
            ? conduitKeyOne
            : bytes32(0);

        uint256 paymentAmount = 100 ether;
        uint256 numItemsInBundle = 100;
        uint256 numRuns = 100;
        uint256 tokenId = 0;

        for (uint256 run = 1; run <= numRuns; run++) {
            uint256 sumPayments = 0;

            for (uint256 item = 0; item < numItemsInBundle; item++) {
                tokenId++;
                test721_1.mint(alice, tokenId);
    
                 offerItems.push(
                    OfferItem(
                        ItemType.ERC721,
                        address(test721_1),
                        tokenId,
                        1,
                        1
                    )
                );
                considerationItems.push(
                    ConsiderationItem(
                        ItemType.NATIVE,
                        address(0),
                        0,
                        paymentAmount,
                        paymentAmount,
                        payable(alice)
                    )
                );
                sumPayments += paymentAmount;
            }
    
            OrderComponents memory orderComponents = OrderComponents(
                alice,
                inputs.zone,
                offerItems,
                considerationItems,
                OrderType.FULL_OPEN,
                block.timestamp,
                block.timestamp + 1,
                inputs.zoneHash,
                inputs.salt,
                conduitKey,
                seaport.getCounter(alice)
            );
    
            bytes memory signature = signOrder(
                seaport,
                alicePk,
                seaport.getOrderHash(orderComponents)
            );
    
            OrderParameters memory orderParameters = OrderParameters(
                address(alice),
                inputs.zone,
                offerItems,
                considerationItems,
                OrderType.FULL_OPEN,
                block.timestamp,
                block.timestamp + 1,
                inputs.zoneHash,
                inputs.salt,
                conduitKey,
                considerationItems.length
            );
    
            vm.prank(bob);
            seaport.fulfillOrder{value: sumPayments}(Order(orderParameters, signature), conduitKey);

            delete offerItems;
            delete considerationItems;
            delete basicOrderParameters;
            delete baseOrderComponents;
        }
    }

    // Bundled Listing No Fees, Native Eth Payment, Use Conduit
    function test_benchmarkBuyBundledListingNoFeesUseConduit(FuzzInputsCommonFulfillOrder memory inputs) public {
        vm.assume(inputs.useConduit == true);

        bytes32 conduitKey = inputs.useConduit
            ? conduitKeyOne
            : bytes32(0);

        uint256 paymentAmount = 100 ether;
        uint256 numItemsInBundle = 100;
        uint256 numRuns = 100;
        uint256 tokenId = 0;

        for (uint256 run = 1; run <= numRuns; run++) {
            uint256 sumPayments = 0;

            for (uint256 item = 0; item < numItemsInBundle; item++) {
                tokenId++;
                test721_1.mint(alice, tokenId);
    
                 offerItems.push(
                    OfferItem(
                        ItemType.ERC721,
                        address(test721_1),
                        tokenId,
                        1,
                        1
                    )
                );
                considerationItems.push(
                    ConsiderationItem(
                        ItemType.NATIVE,
                        address(0),
                        0,
                        paymentAmount,
                        paymentAmount,
                        payable(alice)
                    )
                );
                sumPayments += paymentAmount;
            }
    
            OrderComponents memory orderComponents = OrderComponents(
                alice,
                inputs.zone,
                offerItems,
                considerationItems,
                OrderType.FULL_OPEN,
                block.timestamp,
                block.timestamp + 1,
                inputs.zoneHash,
                inputs.salt,
                conduitKey,
                seaport.getCounter(alice)
            );
    
            bytes memory signature = signOrder(
                seaport,
                alicePk,
                seaport.getOrderHash(orderComponents)
            );
    
            OrderParameters memory orderParameters = OrderParameters(
                address(alice),
                inputs.zone,
                offerItems,
                considerationItems,
                OrderType.FULL_OPEN,
                block.timestamp,
                block.timestamp + 1,
                inputs.zoneHash,
                inputs.salt,
                conduitKey,
                considerationItems.length
            );
    
            vm.prank(bob);
            seaport.fulfillOrder{value: sumPayments}(Order(orderParameters, signature), conduitKey);

            delete offerItems;
            delete considerationItems;
            delete basicOrderParameters;
            delete baseOrderComponents;
        }
    }

    // Bundled Listing, 1 Fee Receiver, Native Eth Payment, No Conduit
    function test_benchmarkBuyBundledListingMarketplaceFeesNoConduit(FuzzInputsCommonFulfillOrder memory inputs) public {
        vm.assume(inputs.useConduit == false);

        bytes32 conduitKey = inputs.useConduit
            ? conduitKeyOne
            : bytes32(0);

        uint256 alicePaymentAmount = 95 ether;
        uint256 calPaymentAmount = 5 ether;
        uint256 numItemsInBundle = 100;
        uint256 numRuns = 100;
        uint256 tokenId = 0;

        for (uint256 run = 1; run <= numRuns; run++) {
            uint256 sumPayments = 0;

            for (uint256 item = 0; item < numItemsInBundle; item++) {
                tokenId++;
                test721_1.mint(alice, tokenId);
    
                 offerItems.push(
                    OfferItem(
                        ItemType.ERC721,
                        address(test721_1),
                        tokenId,
                        1,
                        1
                    )
                );
                considerationItems.push(
                    ConsiderationItem(
                        ItemType.NATIVE,
                        address(0),
                        0,
                        alicePaymentAmount,
                        alicePaymentAmount,
                        payable(alice)
                    )
                );
    
                considerationItems.push(
                    ConsiderationItem(
                        ItemType.NATIVE,
                        address(0),
                        0,
                        calPaymentAmount,
                        calPaymentAmount,
                        payable(cal)
                    )
                );
    
                sumPayments += (alicePaymentAmount + calPaymentAmount);
            }
    
            OrderComponents memory orderComponents = OrderComponents(
                alice,
                inputs.zone,
                offerItems,
                considerationItems,
                OrderType.FULL_OPEN,
                block.timestamp,
                block.timestamp + 1,
                inputs.zoneHash,
                inputs.salt,
                conduitKey,
                seaport.getCounter(alice)
            );
    
            bytes memory signature = signOrder(
                seaport,
                alicePk,
                seaport.getOrderHash(orderComponents)
            );
    
            OrderParameters memory orderParameters = OrderParameters(
                address(alice),
                inputs.zone,
                offerItems,
                considerationItems,
                OrderType.FULL_OPEN,
                block.timestamp,
                block.timestamp + 1,
                inputs.zoneHash,
                inputs.salt,
                conduitKey,
                considerationItems.length
            );
    
            vm.prank(bob);
            seaport.fulfillOrder{value: sumPayments}(Order(orderParameters, signature), conduitKey);

            delete offerItems;
            delete considerationItems;
            delete basicOrderParameters;
            delete baseOrderComponents;
        }
    }

    // Bundled Listing, 1 Fee Receiver, Native Eth Payment, Use Conduit
    function test_benchmarkBuyBundledListingMarketplaceFeesUseConduit(FuzzInputsCommonFulfillOrder memory inputs) public {
        vm.assume(inputs.useConduit == true);

        bytes32 conduitKey = inputs.useConduit
            ? conduitKeyOne
            : bytes32(0);

        uint256 alicePaymentAmount = 95 ether;
        uint256 calPaymentAmount = 5 ether;
        uint256 numItemsInBundle = 100;
        uint256 numRuns = 100;
        uint256 tokenId = 0;

        for (uint256 run = 1; run <= numRuns; run++) {
            uint256 sumPayments = 0;

            for (uint256 item = 0; item < numItemsInBundle; item++) {
                tokenId++;
                test721_1.mint(alice, tokenId);
    
                 offerItems.push(
                    OfferItem(
                        ItemType.ERC721,
                        address(test721_1),
                        tokenId,
                        1,
                        1
                    )
                );
                considerationItems.push(
                    ConsiderationItem(
                        ItemType.NATIVE,
                        address(0),
                        0,
                        alicePaymentAmount,
                        alicePaymentAmount,
                        payable(alice)
                    )
                );
    
                considerationItems.push(
                    ConsiderationItem(
                        ItemType.NATIVE,
                        address(0),
                        0,
                        calPaymentAmount,
                        calPaymentAmount,
                        payable(cal)
                    )
                );
    
                sumPayments += (alicePaymentAmount + calPaymentAmount);
            }
    
            OrderComponents memory orderComponents = OrderComponents(
                alice,
                inputs.zone,
                offerItems,
                considerationItems,
                OrderType.FULL_OPEN,
                block.timestamp,
                block.timestamp + 1,
                inputs.zoneHash,
                inputs.salt,
                conduitKey,
                seaport.getCounter(alice)
            );
    
            bytes memory signature = signOrder(
                seaport,
                alicePk,
                seaport.getOrderHash(orderComponents)
            );
    
            OrderParameters memory orderParameters = OrderParameters(
                address(alice),
                inputs.zone,
                offerItems,
                considerationItems,
                OrderType.FULL_OPEN,
                block.timestamp,
                block.timestamp + 1,
                inputs.zoneHash,
                inputs.salt,
                conduitKey,
                considerationItems.length
            );
    
            vm.prank(bob);
            seaport.fulfillOrder{value: sumPayments}(Order(orderParameters, signature), conduitKey);

            delete offerItems;
            delete considerationItems;
            delete basicOrderParameters;
            delete baseOrderComponents;
        }
    }

    // Bundled Listing, 2 Fee Receivers, Native Eth Payment, No Conduit
    function test_benchmarkBuyBundledListingMarketplaceAndRoyaltyFeesNoConduit(FuzzInputsCommonFulfillOrder memory inputs) public {
        vm.assume(inputs.useConduit == false);

        bytes32 conduitKey = inputs.useConduit
            ? conduitKeyOne
            : bytes32(0);

        uint256 alicePaymentAmount = 85 ether;
        uint256 calPaymentAmount = 5 ether;
        uint256 abePaymentAmount = 10 ether;
        uint256 numItemsInBundle = 100;
        uint256 numRuns = 100;
        uint256 tokenId = 0;

        for (uint256 run = 1; run <= numRuns; run++) {
            uint256 sumPayments = 0;

            for (uint256 item = 0; item < numItemsInBundle; item++) {
                tokenId++;
                test721_1.mint(alice, tokenId);
    
                 offerItems.push(
                    OfferItem(
                        ItemType.ERC721,
                        address(test721_1),
                        tokenId,
                        1,
                        1
                    )
                );
                considerationItems.push(
                    ConsiderationItem(
                        ItemType.NATIVE,
                        address(0),
                        0,
                        alicePaymentAmount,
                        alicePaymentAmount,
                        payable(alice)
                    )
                );
    
                considerationItems.push(
                    ConsiderationItem(
                        ItemType.NATIVE,
                        address(0),
                        0,
                        calPaymentAmount,
                        calPaymentAmount,
                        payable(cal)
                    )
                );
    
                considerationItems.push(
                    ConsiderationItem(
                        ItemType.NATIVE,
                        address(0),
                        0,
                        abePaymentAmount,
                        abePaymentAmount,
                        payable(abe)
                    )
                );
    
                sumPayments += (alicePaymentAmount + calPaymentAmount + abePaymentAmount);
            }
    
            OrderComponents memory orderComponents = OrderComponents(
                alice,
                inputs.zone,
                offerItems,
                considerationItems,
                OrderType.FULL_OPEN,
                block.timestamp,
                block.timestamp + 1,
                inputs.zoneHash,
                inputs.salt,
                conduitKey,
                seaport.getCounter(alice)
            );
    
            bytes memory signature = signOrder(
                seaport,
                alicePk,
                seaport.getOrderHash(orderComponents)
            );
    
            OrderParameters memory orderParameters = OrderParameters(
                address(alice),
                inputs.zone,
                offerItems,
                considerationItems,
                OrderType.FULL_OPEN,
                block.timestamp,
                block.timestamp + 1,
                inputs.zoneHash,
                inputs.salt,
                conduitKey,
                considerationItems.length
            );
    
            vm.prank(bob);
            seaport.fulfillOrder{value: sumPayments}(Order(orderParameters, signature), conduitKey);

            delete offerItems;
            delete considerationItems;
            delete basicOrderParameters;
            delete baseOrderComponents;
        }
    }

    // Bundled Listing, 2 Fee Receivers, Native Eth Payment, Use Conduit
    function test_benchmarkBuyBundledListingMarketplaceAndRoyaltyFeesUseConduit(FuzzInputsCommonFulfillOrder memory inputs) public {
        vm.assume(inputs.useConduit == true);

        bytes32 conduitKey = inputs.useConduit
            ? conduitKeyOne
            : bytes32(0);

        uint256 alicePaymentAmount = 85 ether;
        uint256 calPaymentAmount = 5 ether;
        uint256 abePaymentAmount = 10 ether;
        uint256 numItemsInBundle = 100;
        uint256 numRuns = 100;
        uint256 tokenId = 0;

        for (uint256 run = 1; run <= numRuns; run++) {
            uint256 sumPayments = 0;

            for (uint256 item = 0; item < numItemsInBundle; item++) {
                tokenId++;
                test721_1.mint(alice, tokenId);
    
                 offerItems.push(
                    OfferItem(
                        ItemType.ERC721,
                        address(test721_1),
                        tokenId,
                        1,
                        1
                    )
                );
                considerationItems.push(
                    ConsiderationItem(
                        ItemType.NATIVE,
                        address(0),
                        0,
                        alicePaymentAmount,
                        alicePaymentAmount,
                        payable(alice)
                    )
                );
    
                considerationItems.push(
                    ConsiderationItem(
                        ItemType.NATIVE,
                        address(0),
                        0,
                        calPaymentAmount,
                        calPaymentAmount,
                        payable(cal)
                    )
                );
    
                considerationItems.push(
                    ConsiderationItem(
                        ItemType.NATIVE,
                        address(0),
                        0,
                        abePaymentAmount,
                        abePaymentAmount,
                        payable(abe)
                    )
                );
    
                sumPayments += (alicePaymentAmount + calPaymentAmount + abePaymentAmount);
            }
    
            OrderComponents memory orderComponents = OrderComponents(
                alice,
                inputs.zone,
                offerItems,
                considerationItems,
                OrderType.FULL_OPEN,
                block.timestamp,
                block.timestamp + 1,
                inputs.zoneHash,
                inputs.salt,
                conduitKey,
                seaport.getCounter(alice)
            );
    
            bytes memory signature = signOrder(
                seaport,
                alicePk,
                seaport.getOrderHash(orderComponents)
            );
    
            OrderParameters memory orderParameters = OrderParameters(
                address(alice),
                inputs.zone,
                offerItems,
                considerationItems,
                OrderType.FULL_OPEN,
                block.timestamp,
                block.timestamp + 1,
                inputs.zoneHash,
                inputs.salt,
                conduitKey,
                considerationItems.length
            );
    
            vm.prank(bob);
            seaport.fulfillOrder{value: sumPayments}(Order(orderParameters, signature), conduitKey);

            delete offerItems;
            delete considerationItems;
            delete basicOrderParameters;
            delete baseOrderComponents;
        }
    }

    function test_benchmarkSweepCollectionNoFeesNoConduit(FuzzInputsCommonFulfillOrder memory inputs) public {
        vm.assume(inputs.useConduit == false);

        bytes32 conduitKey = inputs.useConduit
            ? conduitKeyOne
            : bytes32(0);

        uint256 paymentAmount = 100 ether;
        uint256 numItemsInBundle = 100;
        uint256 numRuns = 50;
        uint256 tokenId = 0;

        for (uint256 i = 0; i < numItemsInBundle; i++) {
                uint256 fakeAddressPk = 1000000 + i;
                address fakeAddress = vm.addr(fakeAddressPk);

                vm.startPrank(fakeAddress);
                test721_1.setApprovalForAll(address(seaport), true);
                test721_1.setApprovalForAll(address(conduit), true);
                vm.stopPrank();
        }

        for (uint256 run = 1; run <= numRuns; run++) {
            uint256 sumPayments = 0;
   
            AdvancedOrder[] memory advancedOrders = new AdvancedOrder[](numItemsInBundle);
            for (uint256 i = 0; i < numItemsInBundle; i++) {
                uint256 fakeAddressPk = 1000000 + i;
                address fakeAddress = vm.addr(fakeAddressPk);

                tokenId++;
                test721_1.mint(fakeAddress, tokenId);
    
                 offerItems.push(
                    OfferItem(
                        ItemType.ERC721,
                        address(test721_1),
                        tokenId,
                        1,
                        1
                    )
                );
    
                considerationItems.push(
                    ConsiderationItem(
                        ItemType.NATIVE,
                        address(0),
                        0,
                        paymentAmount,
                        paymentAmount,
                        payable(fakeAddress)
                    )
                );
    
                OrderComponents memory orderComponents = OrderComponents(
                    fakeAddress,
                    inputs.zone,
                    offerItems,
                    considerationItems,
                    OrderType.PARTIAL_OPEN,
                    block.timestamp,
                    block.timestamp + 1,
                    inputs.zoneHash,
                    inputs.salt,
                    conduitKey,
                    seaport.getCounter(alice)
                );
       
                OrderParameters memory orderParameters = OrderParameters(
                    fakeAddress,
                    inputs.zone,
                    offerItems,
                    considerationItems,
                    OrderType.PARTIAL_OPEN,
                    block.timestamp,
                    block.timestamp + 1,
                    inputs.zoneHash,
                    inputs.salt,
                    conduitKey,
                    considerationItems.length
                );
    
                advancedOrders[i] = AdvancedOrder(
                    orderParameters,
                    1,
                    1,
                    signOrder(
                        seaport,
                        fakeAddressPk,
                        seaport.getOrderHash(orderComponents)
                    ),
                    "0x"
                );
    
                sumPayments += paymentAmount;
    
                delete offerItems;
                delete considerationItems;
    
                offerComponents.push(FulfillmentComponent(i, 0));
                offerComponentsArray.push(offerComponents);
                delete offerComponents;
    
                considerationComponents.push(FulfillmentComponent(i, 0));
                considerationComponentsArray.push(considerationComponents);
                delete considerationComponents;
            }
      
            vm.prank(bob, bob);
            seaport.fulfillAvailableAdvancedOrders{ value: sumPayments }(
                advancedOrders,
                new CriteriaResolver[](0),
                offerComponentsArray,
                considerationComponentsArray,
                conduitKey,
                address(0),
                100
            );

            delete offerItems;
            delete considerationItems;
            delete basicOrderParameters;
            delete baseOrderComponents;
            delete offerComponentsArray;
            delete considerationComponentsArray;
        }
    }

    function test_benchmarkSweepCollectionNoFeesUseConduit(FuzzInputsCommonFulfillOrder memory inputs) public {
        vm.assume(inputs.useConduit == true);

        bytes32 conduitKey = inputs.useConduit
            ? conduitKeyOne
            : bytes32(0);

        uint256 paymentAmount = 100 ether;
        uint256 numItemsInBundle = 100;
        uint256 numRuns = 50;
        uint256 tokenId = 0;

        for (uint256 i = 0; i < numItemsInBundle; i++) {
                uint256 fakeAddressPk = 1000000 + i;
                address fakeAddress = vm.addr(fakeAddressPk);

                vm.startPrank(fakeAddress);
                test721_1.setApprovalForAll(address(seaport), true);
                test721_1.setApprovalForAll(address(conduit), true);
                vm.stopPrank();
        }

        for (uint256 run = 1; run <= numRuns; run++) {
            uint256 sumPayments = 0;
   
            AdvancedOrder[] memory advancedOrders = new AdvancedOrder[](numItemsInBundle);
            for (uint256 i = 0; i < numItemsInBundle; i++) {
                uint256 fakeAddressPk = 1000000 + i;
                address fakeAddress = vm.addr(fakeAddressPk);

                tokenId++;
                test721_1.mint(fakeAddress, tokenId);
    
                 offerItems.push(
                    OfferItem(
                        ItemType.ERC721,
                        address(test721_1),
                        tokenId,
                        1,
                        1
                    )
                );
    
                considerationItems.push(
                    ConsiderationItem(
                        ItemType.NATIVE,
                        address(0),
                        0,
                        paymentAmount,
                        paymentAmount,
                        payable(fakeAddress)
                    )
                );
    
                OrderComponents memory orderComponents = OrderComponents(
                    fakeAddress,
                    inputs.zone,
                    offerItems,
                    considerationItems,
                    OrderType.PARTIAL_OPEN,
                    block.timestamp,
                    block.timestamp + 1,
                    inputs.zoneHash,
                    inputs.salt,
                    conduitKey,
                    seaport.getCounter(alice)
                );
       
                OrderParameters memory orderParameters = OrderParameters(
                    fakeAddress,
                    inputs.zone,
                    offerItems,
                    considerationItems,
                    OrderType.PARTIAL_OPEN,
                    block.timestamp,
                    block.timestamp + 1,
                    inputs.zoneHash,
                    inputs.salt,
                    conduitKey,
                    considerationItems.length
                );
    
                advancedOrders[i] = AdvancedOrder(
                    orderParameters,
                    1,
                    1,
                    signOrder(
                        seaport,
                        fakeAddressPk,
                        seaport.getOrderHash(orderComponents)
                    ),
                    "0x"
                );
    
                sumPayments += paymentAmount;
    
                delete offerItems;
                delete considerationItems;
    
                offerComponents.push(FulfillmentComponent(i, 0));
                offerComponentsArray.push(offerComponents);
                delete offerComponents;
    
                considerationComponents.push(FulfillmentComponent(i, 0));
                considerationComponentsArray.push(considerationComponents);
                delete considerationComponents;
            }
      
            vm.prank(bob, bob);
            seaport.fulfillAvailableAdvancedOrders{ value: sumPayments }(
                advancedOrders,
                new CriteriaResolver[](0),
                offerComponentsArray,
                considerationComponentsArray,
                conduitKey,
                address(0),
                100
            );

            delete offerItems;
            delete considerationItems;
            delete basicOrderParameters;
            delete baseOrderComponents;
            delete offerComponentsArray;
            delete considerationComponentsArray;
        }
    }

    function test_benchmarkSweepCollectionMarketplaceFeesNoConduit(FuzzInputsCommonFulfillOrder memory inputs) public {
        vm.assume(inputs.useConduit == false);

        bytes32 conduitKey = inputs.useConduit
            ? conduitKeyOne
            : bytes32(0);

        uint256 numItemsInBundle = 100;
        uint256 numRuns = 50;
        uint256 tokenId = 0;

        for (uint256 i = 0; i < numItemsInBundle; i++) {
                uint256 fakeAddressPk = 1000000 + i;
                address fakeAddress = vm.addr(fakeAddressPk);

                vm.startPrank(fakeAddress);
                test721_1.setApprovalForAll(address(seaport), true);
                test721_1.setApprovalForAll(address(conduit), true);
                vm.stopPrank();
        }

        for (uint256 run = 1; run <= numRuns; run++) {
            uint256 sumPayments = 0;
   
            AdvancedOrder[] memory advancedOrders = new AdvancedOrder[](numItemsInBundle);
            for (uint256 i = 0; i < numItemsInBundle; i++) {
                uint256 fakeAddressPk = 1000000 + i;
                address fakeAddress = vm.addr(fakeAddressPk);

                tokenId++;
                test721_1.mint(fakeAddress, tokenId);
    
                 offerItems.push(
                    OfferItem(
                        ItemType.ERC721,
                        address(test721_1),
                        tokenId,
                        1,
                        1
                    )
                );
    
                considerationItems.push(
                    ConsiderationItem(
                        ItemType.NATIVE,
                        address(0),
                        0,
                        95 ether,
                        95 ether,
                        payable(fakeAddress)
                    )
                );

                considerationItems.push(
                    ConsiderationItem(
                        ItemType.NATIVE,
                        address(0),
                        0,
                        5 ether,
                        5 ether,
                        payable(cal)
                    )
                );
    
                OrderComponents memory orderComponents = OrderComponents(
                    fakeAddress,
                    inputs.zone,
                    offerItems,
                    considerationItems,
                    OrderType.PARTIAL_OPEN,
                    block.timestamp,
                    block.timestamp + 1,
                    inputs.zoneHash,
                    inputs.salt,
                    conduitKey,
                    seaport.getCounter(alice)
                );
       
                OrderParameters memory orderParameters = OrderParameters(
                    fakeAddress,
                    inputs.zone,
                    offerItems,
                    considerationItems,
                    OrderType.PARTIAL_OPEN,
                    block.timestamp,
                    block.timestamp + 1,
                    inputs.zoneHash,
                    inputs.salt,
                    conduitKey,
                    considerationItems.length
                );
    
                advancedOrders[i] = AdvancedOrder(
                    orderParameters,
                    1,
                    1,
                    signOrder(
                        seaport,
                        fakeAddressPk,
                        seaport.getOrderHash(orderComponents)
                    ),
                    "0x"
                );
    
                sumPayments += 100 ether;
    
                delete offerItems;
                delete considerationItems;
    
                offerComponents.push(FulfillmentComponent(i, 0));
                offerComponentsArray.push(offerComponents);
                delete offerComponents;
    
                considerationComponents.push(FulfillmentComponent(i, 0));
                considerationComponentsArray.push(considerationComponents);
                delete considerationComponents;
    
                considerationComponents.push(FulfillmentComponent(i, 1));
                considerationComponentsArray.push(considerationComponents);
                delete considerationComponents;
            }
      
            vm.prank(bob, bob);
            seaport.fulfillAvailableAdvancedOrders{ value: sumPayments }(
                advancedOrders,
                new CriteriaResolver[](0),
                offerComponentsArray,
                considerationComponentsArray,
                conduitKey,
                address(0),
                100
            );

            delete offerItems;
            delete considerationItems;
            delete basicOrderParameters;
            delete baseOrderComponents;
            delete offerComponentsArray;
            delete considerationComponentsArray;
        }
    }

    function test_benchmarkSweepCollectionMarketplaceFeesUseConduit(FuzzInputsCommonFulfillOrder memory inputs) public {
        vm.assume(inputs.useConduit == true);

        bytes32 conduitKey = inputs.useConduit
            ? conduitKeyOne
            : bytes32(0);

        uint256 numItemsInBundle = 100;
        uint256 numRuns = 50;
        uint256 tokenId = 0;

        for (uint256 i = 0; i < numItemsInBundle; i++) {
                uint256 fakeAddressPk = 1000000 + i;
                address fakeAddress = vm.addr(fakeAddressPk);

                vm.startPrank(fakeAddress);
                test721_1.setApprovalForAll(address(seaport), true);
                test721_1.setApprovalForAll(address(conduit), true);
                vm.stopPrank();
        }

        for (uint256 run = 1; run <= numRuns; run++) {
            uint256 sumPayments = 0;
   
            AdvancedOrder[] memory advancedOrders = new AdvancedOrder[](numItemsInBundle);
            for (uint256 i = 0; i < numItemsInBundle; i++) {
                uint256 fakeAddressPk = 1000000 + i;
                address fakeAddress = vm.addr(fakeAddressPk);

                tokenId++;
                test721_1.mint(fakeAddress, tokenId);
    
                 offerItems.push(
                    OfferItem(
                        ItemType.ERC721,
                        address(test721_1),
                        tokenId,
                        1,
                        1
                    )
                );
    
                considerationItems.push(
                    ConsiderationItem(
                        ItemType.NATIVE,
                        address(0),
                        0,
                        95 ether,
                        95 ether,
                        payable(fakeAddress)
                    )
                );

                considerationItems.push(
                    ConsiderationItem(
                        ItemType.NATIVE,
                        address(0),
                        0,
                        5 ether,
                        5 ether,
                        payable(cal)
                    )
                );
    
                OrderComponents memory orderComponents = OrderComponents(
                    fakeAddress,
                    inputs.zone,
                    offerItems,
                    considerationItems,
                    OrderType.PARTIAL_OPEN,
                    block.timestamp,
                    block.timestamp + 1,
                    inputs.zoneHash,
                    inputs.salt,
                    conduitKey,
                    seaport.getCounter(alice)
                );
       
                OrderParameters memory orderParameters = OrderParameters(
                    fakeAddress,
                    inputs.zone,
                    offerItems,
                    considerationItems,
                    OrderType.PARTIAL_OPEN,
                    block.timestamp,
                    block.timestamp + 1,
                    inputs.zoneHash,
                    inputs.salt,
                    conduitKey,
                    considerationItems.length
                );
    
                advancedOrders[i] = AdvancedOrder(
                    orderParameters,
                    1,
                    1,
                    signOrder(
                        seaport,
                        fakeAddressPk,
                        seaport.getOrderHash(orderComponents)
                    ),
                    "0x"
                );
    
                sumPayments += 100 ether;
    
                delete offerItems;
                delete considerationItems;
    
                offerComponents.push(FulfillmentComponent(i, 0));
                offerComponentsArray.push(offerComponents);
                delete offerComponents;
    
                considerationComponents.push(FulfillmentComponent(i, 0));
                considerationComponentsArray.push(considerationComponents);
                delete considerationComponents;
    
                considerationComponents.push(FulfillmentComponent(i, 1));
                considerationComponentsArray.push(considerationComponents);
                delete considerationComponents;
            }
      
            vm.prank(bob, bob);
            seaport.fulfillAvailableAdvancedOrders{ value: sumPayments }(
                advancedOrders,
                new CriteriaResolver[](0),
                offerComponentsArray,
                considerationComponentsArray,
                conduitKey,
                address(0),
                100
            );

            delete offerItems;
            delete considerationItems;
            delete basicOrderParameters;
            delete baseOrderComponents;
            delete offerComponentsArray;
            delete considerationComponentsArray;
        }
    }

    function test_benchmarkSweepCollectionMarketplaceAndRoyaltyFeesNoConduit(FuzzInputsCommonFulfillOrder memory inputs) public {
        vm.assume(inputs.useConduit == false);

        bytes32 conduitKey = inputs.useConduit
            ? conduitKeyOne
            : bytes32(0);

        uint256 numItemsInBundle = 100;
        uint256 numRuns = 45;
        uint256 tokenId = 0;

        for (uint256 i = 0; i < numItemsInBundle; i++) {
                uint256 fakeAddressPk = 1000000 + i;
                address fakeAddress = vm.addr(fakeAddressPk);

                vm.startPrank(fakeAddress);
                test721_1.setApprovalForAll(address(seaport), true);
                test721_1.setApprovalForAll(address(conduit), true);
                vm.stopPrank();
        }

        for (uint256 run = 1; run <= numRuns; run++) {
            uint256 sumPayments = 0;
   
            AdvancedOrder[] memory advancedOrders = new AdvancedOrder[](numItemsInBundle);
            for (uint256 i = 0; i < numItemsInBundle; i++) {
                uint256 fakeAddressPk = 1000000 + i;
                address fakeAddress = vm.addr(fakeAddressPk);

                tokenId++;
                test721_1.mint(fakeAddress, tokenId);
    
                 offerItems.push(
                    OfferItem(
                        ItemType.ERC721,
                        address(test721_1),
                        tokenId,
                        1,
                        1
                    )
                );
    
                considerationItems.push(
                    ConsiderationItem(
                        ItemType.NATIVE,
                        address(0),
                        0,
                        85 ether,
                        85 ether,
                        payable(fakeAddress)
                    )
                );

                considerationItems.push(
                    ConsiderationItem(
                        ItemType.NATIVE,
                        address(0),
                        0,
                        5 ether,
                        5 ether,
                        payable(cal)
                    )
                );

                considerationItems.push(
                    ConsiderationItem(
                        ItemType.NATIVE,
                        address(0),
                        0,
                        10 ether,
                        10 ether,
                        payable(abe)
                    )
                );
    
                OrderComponents memory orderComponents = OrderComponents(
                    fakeAddress,
                    inputs.zone,
                    offerItems,
                    considerationItems,
                    OrderType.PARTIAL_OPEN,
                    block.timestamp,
                    block.timestamp + 1,
                    inputs.zoneHash,
                    inputs.salt,
                    conduitKey,
                    seaport.getCounter(alice)
                );
       
                OrderParameters memory orderParameters = OrderParameters(
                    fakeAddress,
                    inputs.zone,
                    offerItems,
                    considerationItems,
                    OrderType.PARTIAL_OPEN,
                    block.timestamp,
                    block.timestamp + 1,
                    inputs.zoneHash,
                    inputs.salt,
                    conduitKey,
                    considerationItems.length
                );
    
                advancedOrders[i] = AdvancedOrder(
                    orderParameters,
                    1,
                    1,
                    signOrder(
                        seaport,
                        fakeAddressPk,
                        seaport.getOrderHash(orderComponents)
                    ),
                    "0x"
                );
    
                sumPayments += 100 ether;
    
                delete offerItems;
                delete considerationItems;
    
                offerComponents.push(FulfillmentComponent(i, 0));
                offerComponentsArray.push(offerComponents);
                delete offerComponents;
    
                considerationComponents.push(FulfillmentComponent(i, 0));
                considerationComponentsArray.push(considerationComponents);
                delete considerationComponents;
    
                considerationComponents.push(FulfillmentComponent(i, 1));
                considerationComponentsArray.push(considerationComponents);
                delete considerationComponents;

                considerationComponents.push(FulfillmentComponent(i, 2));
                considerationComponentsArray.push(considerationComponents);
                delete considerationComponents;
            }
      
            vm.prank(bob, bob);
            seaport.fulfillAvailableAdvancedOrders{ value: sumPayments }(
                advancedOrders,
                new CriteriaResolver[](0),
                offerComponentsArray,
                considerationComponentsArray,
                conduitKey,
                address(0),
                100
            );

            delete offerItems;
            delete considerationItems;
            delete basicOrderParameters;
            delete baseOrderComponents;
            delete offerComponentsArray;
            delete considerationComponentsArray;
        }
    }

    function test_benchmarkSweepCollectionMarketplaceAndRoyaltyFeesUseConduit(FuzzInputsCommonFulfillOrder memory inputs) public {
        vm.assume(inputs.useConduit == true);

        bytes32 conduitKey = inputs.useConduit
            ? conduitKeyOne
            : bytes32(0);

        uint256 numItemsInBundle = 100;
        uint256 numRuns = 45;
        uint256 tokenId = 0;

        for (uint256 i = 0; i < numItemsInBundle; i++) {
                uint256 fakeAddressPk = 1000000 + i;
                address fakeAddress = vm.addr(fakeAddressPk);

                vm.startPrank(fakeAddress);
                test721_1.setApprovalForAll(address(seaport), true);
                test721_1.setApprovalForAll(address(conduit), true);
                vm.stopPrank();
        }

        for (uint256 run = 1; run <= numRuns; run++) {
            uint256 sumPayments = 0;
   
            AdvancedOrder[] memory advancedOrders = new AdvancedOrder[](numItemsInBundle);
            for (uint256 i = 0; i < numItemsInBundle; i++) {
                uint256 fakeAddressPk = 1000000 + i;
                address fakeAddress = vm.addr(fakeAddressPk);

                tokenId++;
                test721_1.mint(fakeAddress, tokenId);
    
                 offerItems.push(
                    OfferItem(
                        ItemType.ERC721,
                        address(test721_1),
                        tokenId,
                        1,
                        1
                    )
                );
    
                considerationItems.push(
                    ConsiderationItem(
                        ItemType.NATIVE,
                        address(0),
                        0,
                        85 ether,
                        85 ether,
                        payable(fakeAddress)
                    )
                );

                considerationItems.push(
                    ConsiderationItem(
                        ItemType.NATIVE,
                        address(0),
                        0,
                        5 ether,
                        5 ether,
                        payable(cal)
                    )
                );

                considerationItems.push(
                    ConsiderationItem(
                        ItemType.NATIVE,
                        address(0),
                        0,
                        10 ether,
                        10 ether,
                        payable(abe)
                    )
                );
    
                OrderComponents memory orderComponents = OrderComponents(
                    fakeAddress,
                    inputs.zone,
                    offerItems,
                    considerationItems,
                    OrderType.PARTIAL_OPEN,
                    block.timestamp,
                    block.timestamp + 1,
                    inputs.zoneHash,
                    inputs.salt,
                    conduitKey,
                    seaport.getCounter(alice)
                );
       
                OrderParameters memory orderParameters = OrderParameters(
                    fakeAddress,
                    inputs.zone,
                    offerItems,
                    considerationItems,
                    OrderType.PARTIAL_OPEN,
                    block.timestamp,
                    block.timestamp + 1,
                    inputs.zoneHash,
                    inputs.salt,
                    conduitKey,
                    considerationItems.length
                );
    
                advancedOrders[i] = AdvancedOrder(
                    orderParameters,
                    1,
                    1,
                    signOrder(
                        seaport,
                        fakeAddressPk,
                        seaport.getOrderHash(orderComponents)
                    ),
                    "0x"
                );
    
                sumPayments += 100 ether;
    
                delete offerItems;
                delete considerationItems;
    
                offerComponents.push(FulfillmentComponent(i, 0));
                offerComponentsArray.push(offerComponents);
                delete offerComponents;
    
                considerationComponents.push(FulfillmentComponent(i, 0));
                considerationComponentsArray.push(considerationComponents);
                delete considerationComponents;
    
                considerationComponents.push(FulfillmentComponent(i, 1));
                considerationComponentsArray.push(considerationComponents);
                delete considerationComponents;

                considerationComponents.push(FulfillmentComponent(i, 2));
                considerationComponentsArray.push(considerationComponents);
                delete considerationComponents;
            }
      
            vm.prank(bob, bob);
            seaport.fulfillAvailableAdvancedOrders{ value: sumPayments }(
                advancedOrders,
                new CriteriaResolver[](0),
                offerComponentsArray,
                considerationComponentsArray,
                conduitKey,
                address(0),
                100
            );

            delete offerItems;
            delete considerationItems;
            delete basicOrderParameters;
            delete baseOrderComponents;
            delete offerComponentsArray;
            delete considerationComponentsArray;
        }
    }

    function _configureBasicOrderParametersEthTo721(
        FuzzInputsCommon memory args
    ) internal {
        basicOrderParameters.considerationToken = address(0);
        basicOrderParameters.considerationIdentifier = 0;
        basicOrderParameters.considerationAmount = args.paymentAmount;
        basicOrderParameters.offerer = payable(alice);
        basicOrderParameters.zone = args.zone;
        basicOrderParameters.offerToken = address(test721_1);
        basicOrderParameters.offerIdentifier = args.tokenId;
        basicOrderParameters.offerAmount = 1;
        basicOrderParameters.basicOrderType = BasicOrderType
            .ETH_TO_ERC721_FULL_OPEN;
        basicOrderParameters.startTime = block.timestamp;
        basicOrderParameters.endTime = block.timestamp + 100;
        basicOrderParameters.zoneHash = args.zoneHash;
        basicOrderParameters.salt = args.salt;
        basicOrderParameters.offererConduitKey = args.useConduit
            ? conduitKeyOne
            : bytes32(0);
        basicOrderParameters.fulfillerConduitKey = bytes32(0);
        basicOrderParameters.totalOriginalAdditionalRecipients = 0;
        // additional recipients should always be empty
        // don't do signature;
    }

    function _configureBasicOrderParametersEthTo1155(
        FuzzInputsCommon memory args,
        uint128 amount
    ) internal {
        basicOrderParameters.considerationToken = address(0);
        basicOrderParameters.considerationIdentifier = 0;
        basicOrderParameters.considerationAmount = args.paymentAmount;
        basicOrderParameters.offerer = payable(alice);
        basicOrderParameters.zone = args.zone;
        basicOrderParameters.offerToken = address(test1155_1);
        basicOrderParameters.offerIdentifier = args.tokenId;
        basicOrderParameters.offerAmount = amount;
        basicOrderParameters.basicOrderType = BasicOrderType
            .ETH_TO_ERC1155_FULL_OPEN;
        basicOrderParameters.startTime = block.timestamp;
        basicOrderParameters.endTime = block.timestamp + 100;
        basicOrderParameters.zoneHash = args.zoneHash;
        basicOrderParameters.salt = args.salt;
        basicOrderParameters.offererConduitKey = args.useConduit
            ? conduitKeyOne
            : bytes32(0);
        basicOrderParameters.fulfillerConduitKey = bytes32(0);
        basicOrderParameters.totalOriginalAdditionalRecipients = 0;
        // additional recipients should always be empty
        // don't do signature;
    }

    function _configureBasicOrderParametersErc20To1155(
        FuzzInputsCommon memory args,
        uint128 amount
    ) internal {
        _configureBasicOrderParametersEthTo1155(args, amount);
        basicOrderParameters.considerationToken = address(token1);
        basicOrderParameters.basicOrderType = BasicOrderType
            .ERC20_TO_ERC1155_FULL_OPEN;
    }

    function _configureBasicOrderParametersErc20To721(
        FuzzInputsCommon memory args
    ) internal {
        _configureBasicOrderParametersEthTo721(args);
        basicOrderParameters.considerationToken = address(token1);
        basicOrderParameters.basicOrderType = BasicOrderType
            .ERC20_TO_ERC721_FULL_OPEN;
    }

    function configureOrderComponents(
        address zone,
        bytes32 zoneHash,
        uint256 salt,
        bytes32 conduitKey
    ) internal {
        baseOrderComponents.offerer = alice;
        baseOrderComponents.zone = zone;
        baseOrderComponents.offer = offerItems;
        baseOrderComponents.consideration = considerationItems;
        baseOrderComponents.orderType = OrderType.FULL_OPEN;
        baseOrderComponents.startTime = block.timestamp;
        baseOrderComponents.endTime = block.timestamp + 100;
        baseOrderComponents.zoneHash = zoneHash;
        baseOrderComponents.salt = salt;
        baseOrderComponents.conduitKey = conduitKey;
        // don't set counter
    }
}
