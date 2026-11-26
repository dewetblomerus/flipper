# Fields

Field names by module, with limits and fees.

| Module | Fields |
| --- | --- |
| `TITLE` | `title` (80, required), `subtitle` (55, $2 fee), `customLabel` (50), `subtitlePref`, `customLabelPref`, `boldTitlePref`, `boldTitle` ($4 fee) |
| `ATTRIBUTES` | `attributeList`, `universalProductCode` (20), `attributeViewSelection` (`summary`, `selectOwnDetails`), `collapseAttributeOptions`, `attributeBuckets`, `additionalAttributeName`, `additionalAttributeValue` |
| `CONDITION` | `condition` (numeric id), `itemConditionDescription` (1000) |
| `DESCRIPTION` | `description`, `descriptionEditorMode` |
| `PRICE` | `format`, `price`, `quantity`, `bestOfferPref`, `lotSize`, `lotSizePref`, `vpPref`, `costOfGoodsPref`, `paymentPolicyId`, `scheduleStartDate` |
| `VOLUME_PRICING` | `tierOption2`–`4`, `tierRate2`–`4` |
| `CATEGORY` | `categoryId`, `secondaryCategoryId`, `primaryStoreCategoryId`, `secondaryStoreCategoryId` |
| `CHARITY` | `charityId`, `donationPercent` |
| `PROMOTED_LISTING_STANDARD` | `adRate`, `campaignId` |
| `PROMOTED_LISTING_ADVANCED` | `promotedListingsAdvancedCampaignId`, `campaignBudget`, `promotedListingsAdvancedEndDate` |

`SHIPPING` holds:

- Package: `packageLength`, `packageWidth`, `packageDepth`, `majorWeight`, `minorWeight`
- Domestic: `domesticShippingType`, `domesticShippingService1`, `domesticShippingPrice1`, `domesticShippingExtraPrice1`, `domesticShippingRateTableId`, `domesticExcludeShippingLocations`, `shippingDomesticDiscountProfileId`
- International: `intlShippingType`, `intlShippingRegion`, `intlShippingRegion1`, `intlShippingRegions1`, `intlShippingLocations`, `intlExcludeShippingLocations`
- Handling and location: `additionalExcludeShippingLocations`, `localPickupFee`, `shippingPolicyId`, `handlingDuration`, `itemLocation`, `itemLocationCountry`, `itemLocationCityState`
- Returns: `returnPolicy`, `returnDuration`, `returnShippingPayer`, `refundMethod`, `intlReturnPolicy`, `returnsPolicyId`

Other modules: `VARIATIONS`, `REGULATORY_COMPLIANCE`, `AUTHENTICITY_GUARANTEE`, `CTA`, `TOOL_SWITCH`, `GLOBAL`, `GLOBAL_MESSAGE`, `FEE`, `CIM`, `BUSINESS_PROGRAM_CONTENTS`, `LEGAL_AND_FAQ`, `URL`, `HEADER`, `VIDEOS`, `OCS`.
