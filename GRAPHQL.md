# Magento GraphQL API

GraphQL is an API for Magento storefront and customer workflows, including catalog browsing, accounts, carts, checkout, orders, wishlists, comparisons, reviews, and CMS content. Use REST for administrative operations such as creating products and updating inventory; see [API.md](API.md).

Queries read data. Mutations change data. Both use the same endpoint.

## URL and request format

Start Magento with `./start.sh` before sending requests.

| Setting | Value |
| --- | --- |
| Local endpoint | http://localhost:8080/graphql |
| Method for the examples below | `POST` |
| Content type | `application/json` |
| Store view header | `Store: default` |
| Authorization for protected operations | `Authorization: Bearer YOUR_CUSTOMER_TOKEN` |

The JSON request body contains `query`, with optional `variables` and `operationName`. Mutations require POST; queries also support GET. The `Store` header selects the store view and is optional when using the default store.

GraphQL responses can contain `errors` even when the HTTP status is 200. Check the response's `data` and `errors` fields.

Example public catalog query:

```bash
curl -sS http://localhost:8080/graphql \
  -H 'Content-Type: application/json' \
  -H 'Store: default' \
  --data '{"query":"query { products(search: \"shirt\", pageSize: 5) { total_count items { sku name } } }"}'
```

## Authentication

### Public and guest operations

Public catalog and CMS queries do not require a token. Guest cart operations use the guest cart ID and do not require a customer login. Access requirements depend on the operation: fields such as `customer` and `customerCart` require a customer token.

### Customer authentication

Customers authenticate using their customer account email and password, rather than the admin credentials in `.env`.

Request a customer token by replacing `YOUR_CUSTOMER_EMAIL` and `YOUR_CUSTOMER_PASSWORD` below:

```bash
curl -sS http://localhost:8080/graphql \
  -H 'Content-Type: application/json' \
  -H 'Store: default' \
  --data '{"query":"mutation Login($email: String!, $password: String!) { generateCustomerToken(email: $email, password: $password) { token } }","variables":{"email":"YOUR_CUSTOMER_EMAIL","password":"YOUR_CUSTOMER_PASSWORD"}}'
```

Copy the value of `data.generateCustomerToken.token` into the authorization header of subsequent requests:

```bash
curl -sS http://localhost:8080/graphql \
  -H 'Content-Type: application/json' \
  -H 'Store: default' \
  -H 'Authorization: Bearer YOUR_CUSTOMER_TOKEN' \
  --data '{"query":"query { customer { firstname lastname email } customerCart { id total_quantity } }"}'
```

The token grants access to that customer's resources. Use `revokeCustomerToken` with the same authorization header to revoke it. See the [GraphQL authorization documentation](https://developer.adobe.com/commerce/webapi/graphql/usage/authorization-tokens) for token lifetimes and session-cookie behavior.

### Admin authentication

GraphQL does not provide a mutation that generates an admin token. For this local installation, obtain one through the REST endpoint shown in [API.md](API.md):

```bash
curl -sS http://localhost:8080/rest/default/V1/integration/admin/token \
  -H 'Content-Type: application/json' \
  --data '{"username":"admin","password":"YOUR_ADMIN_PASSWORD"}'
```

Replace `YOUR_ADMIN_PASSWORD` with `MAGENTO_ADMIN_PASSWORD` from `.env`. An admin token does not act as a customer token or add administrative catalog-management operations to GraphQL. The schema includes the specialized `generateCustomerTokenAsAdmin` mutation for authorized remote shopping assistance; it requires the relevant permissions and the customer's consent to remote assistance. Use REST for normal administrative integrations.

## Exploring the schema

The operation reference below was generated from the running local instance's GraphQL introspection schema on 2026-10-13. It contains **27 non-deprecated queries and 59 non-deprecated mutations**. The instance also exposes six deprecated queries and six deprecated mutations; these are excluded from the counts and tables below.

Counts and signatures can change when modules or Magento versions change. The live schema is the authority for this checkout, and may differ from a published release's documentation.

The tables specify every current root operation's arguments, default values, return type, and schema description. Type notation follows GraphQL:

- `String!` means a non-null string. A non-null argument without a default value must be supplied.
- `[CartItemInput!]!` means a non-null list of non-null `CartItemInput` values.
- `pageSize: Int = 20` means the argument defaults to `20`.
- Object, interface, and union results require a selection of response fields in your query.

Connect a GraphQL client's schema explorer to http://localhost:8080/graphql to browse nested input and response types. This endpoint serves API responses; it does not include a GraphQL editor page.

This read-only request lists current operation names and descriptions:

```bash
curl -sS http://localhost:8080/graphql \
  -H 'Content-Type: application/json' \
  --data '{"query":"query { __schema { queryType { fields { name description } } mutationType { fields { name description } } } }"}'
```

For the fields of an input or response type named in the tables, use `__type`. Replace `CustomerCreateInput` with the desired type name:

```graphql
query InspectType {
  __type(name: "CustomerCreateInput") {
    name
    kind
    description
    inputFields {
      name
      description
      defaultValue
      type {
        kind
        name
        ofType {
          kind
          name
          ofType {
            kind
            name
            ofType { kind name }
          }
        }
      }
    }
    fields {
      name
      description
      type {
        kind
        name
        ofType {
          kind
          name
          ofType {
            kind
            name
            ofType { kind name }
          }
        }
      }
    }
    enumValues { name description }
  }
}
```

## Official documentation

- [GraphQL overview](https://developer.adobe.com/commerce/webapi/graphql/)
- [GraphQL API reference](https://developer.adobe.com/commerce/webapi/graphql/reference/)
- [Authorization and customer tokens](https://developer.adobe.com/commerce/webapi/graphql/usage/authorization-tokens)
- [Request headers](https://developer.adobe.com/commerce/webapi/graphql/usage/headers)
- [Schema introspection](https://developer.adobe.com/commerce/webapi/graphql/usage/introspection-queries)
- [Cart and checkout mutations](https://developer.adobe.com/commerce/webapi/graphql/schema/cart/mutations/)
- [Customer mutations](https://developer.adobe.com/commerce/webapi/graphql/schema/customer/mutations/)

Use the Magento Open Source/on-premises (PaaS) references for this installation. Some operations in Adobe Commerce documentation require modules that are not present here.

## Query specification (27 operations)

| Operation and arguments | Return type | Description |
| --- | --- | --- |
| `attributesForm(formCode: String!)` | `AttributesFormOutput!` | Retrieve EAV attributes associated to a frontend form. Use countries query provided by DirectoryGraphQl module to retrieve region_id and country_id attribute options. |
| `attributesList(entityType: AttributeEntityTypeEnum!, filters: AttributeFilterInput)` | `AttributesMetadataOutput` | Returns a list of attributes metadata for a given entity type. |
| `availableStores(useCurrentGroup: Boolean)` | `[StoreConfig]` | Get a list of available store views and their config information. |
| `cart(cart_id: String!)` | `Cart` | Return information about the specified shopping cart. |
| `categories(filters: CategoryFilterInput, pageSize: Int = 20, currentPage: Int = 1)` | `CategoryResult` | Return a list of categories that match the specified filter. |
| `checkoutAgreements` | `[CheckoutAgreement]` | Return Terms and Conditions configuration information. |
| `cmsBlocks(identifiers: [String])` | `CmsBlocks` | Return information about CMS blocks. |
| `cmsPage(id: Int, identifier: String)` | `CmsPage` | Return details about a CMS page. |
| `compareList(uid: ID!)` | `CompareList` | Return products that have been added to the specified compare list. |
| `countries` | `[Country]` | The countries query provides information for all countries. |
| `country(id: String)` | `Country` | The countries query provides information for a single country. |
| `currency` | `Currency` | Return information about the store's currency. |
| `customAttributeMetadataV2(attributes: [AttributeInput!])` | `AttributesMetadataOutput!` | Retrieve EAV attributes metadata. |
| `customer` | `Customer` | Return detailed information about a customer account. |
| `customerCart` | `Cart!` | Return information about the customer's shopping cart. |
| `customerDownloadableProducts` | `CustomerDownloadableProducts` | Return a list of downloadable products the customer has purchased. |
| `customerGroup` | `CustomerGroupStorefront!` | Provides Customer Group assigned to the Customer or Guest. |
| `customerPaymentTokens` | `CustomerPaymentTokens` | Return a list of customer payment tokens stored in the vault. |
| `getHostedProUrl(input: HostedProUrlInput!)` | `HostedProUrl` | Retrieve the secure PayPal URL for a Payments Pro Hosted Solution transaction. |
| `getPayflowLinkToken(input: PayflowLinkTokenInput!)` | `PayflowLinkToken` | Retrieve payment credentials for a transaction. Use this query for Payflow Link and Payments Advanced payment methods. |
| `guestOrder(input: GuestOrderInformationInput!)` | `CustomerOrder!` | Retrieve guest order details based on number, email and billing last name. |
| `guestOrderByToken(input: OrderTokenInput!)` | `CustomerOrder!` | Retrieve guest order details based on token. |
| `isEmailAvailable(email: String!)` | `IsEmailAvailableOutput` | Check whether the specified email has already been used to create a customer account. |
| `productReviewRatingsMetadata` | `ProductReviewRatingsMetadata!` | Return the active ratings attributes and the values each rating can have. |
| `products(search: String, filter: ProductAttributeFilterInput, pageSize: Int = 20, currentPage: Int = 1, sort: ProductAttributeSortInput)` | `Products` | Search for products that match the criteria specified in the `search` and `filter` attributes. |
| `route(url: String!)` | `RoutableInterface` | Return the full details for a specified product, category, or CMS page. |
| `storeConfig` | `StoreConfig` | Return details about the store's configuration. |

## Mutation specification (59 operations)

| Operation and arguments | Return type | Description |
| --- | --- | --- |
| `addBundleProductsToCart(input: AddBundleProductsToCartInput)` | `AddBundleProductsToCartOutput` | Add one or more bundle products to the specified cart. We recommend using `addProductsToCart` instead. |
| `addConfigurableProductsToCart(input: AddConfigurableProductsToCartInput)` | `AddConfigurableProductsToCartOutput` | Add one or more configurable products to the specified cart. We recommend using `addProductsToCart` instead. |
| `addDownloadableProductsToCart(input: AddDownloadableProductsToCartInput)` | `AddDownloadableProductsToCartOutput` | Add one or more downloadable products to the specified cart. We recommend using `addProductsToCart` instead. |
| `addProductsToCart(cartId: String!, cartItems: [CartItemInput!]!)` | `AddProductsToCartOutput` | Add any type of product to the cart. |
| `addProductsToCompareList(input: AddProductsToCompareListInput)` | `CompareList` | Add products to the specified compare list. |
| `addProductsToWishlist(wishlistId: ID!, wishlistItems: [WishlistItemInput!]!)` | `AddProductsToWishlistOutput` | Add one or more products to the specified wish list. This mutation supports all product types. |
| `addSimpleProductsToCart(input: AddSimpleProductsToCartInput)` | `AddSimpleProductsToCartOutput` | Add one or more simple products to the specified cart. We recommend using `addProductsToCart` instead. |
| `addVirtualProductsToCart(input: AddVirtualProductsToCartInput)` | `AddVirtualProductsToCartOutput` | Add one or more virtual products to the specified cart. We recommend using `addProductsToCart` instead. |
| `addWishlistItemsToCart(wishlistId: ID!, wishlistItemIds: [ID!])` | `AddWishlistItemsToCartOutput` | Add items in the specified wishlist to the customer's cart. |
| `applyCouponToCart(input: ApplyCouponToCartInput)` | `ApplyCouponToCartOutput` | Apply a pre-defined coupon code to the specified cart. |
| `assignCompareListToCustomer(uid: ID!)` | `AssignCompareListToCustomerOutput` | Assign the specified compare list to the logged in customer. |
| `assignCustomerToGuestCart(cart_id: String!)` | `Cart!` | Assign a logged-in customer to the specified guest shopping cart. |
| `cancelOrder(input: CancelOrderInput!)` | `CancelOrderOutput` | Cancel the specified customer order. |
| `changeCustomerPassword(currentPassword: String!, newPassword: String!)` | `Customer` | Change the password for the logged-in customer. |
| `clearCart(input: ClearCartInput!)` | `ClearCartOutput!` | Remove all items from the specified cart. |
| `clearWishlist(wishlistId: ID!)` | `RemoveProductsFromWishlistOutput` | Remove all the products from the specified wish list. |
| `confirmCancelOrder(input: ConfirmCancelOrderInput!)` | `CancelOrderOutput` | Cancel the specified guest customer order. |
| `confirmEmail(input: ConfirmEmailInput!)` | `CustomerOutput` | Confirms the email address for a customer. |
| `contactUs(input: ContactUsInput!)` | `ContactUsOutput` | Send a 'Contact Us' email to the merchant. |
| `createCompareList(input: CreateCompareListInput)` | `CompareList` | Create a new compare list. The compare list is saved for logged in customers. |
| `createCustomerAddress(input: CustomerAddressInput!)` | `CustomerAddress` | Create a billing or shipping address for a customer or guest. |
| `createCustomerV2(input: CustomerCreateInput!)` | `CustomerOutput` | Create a customer account. |
| `createGuestCart(input: CreateGuestCartInput)` | `CreateGuestCartOutput` | Create a new shopping cart |
| `createPayflowProToken(input: PayflowProTokenInput!)` | `CreatePayflowProTokenOutput` | Initiate a transaction and receive a token. Use this mutation for Payflow Pro and Payments Pro payment methods |
| `createPaypalExpressToken(input: PaypalExpressTokenInput!)` | `PaypalExpressTokenOutput` | Initiate an Express Checkout transaction and receive a token. Use this mutation for Express Checkout and Payments Standard payment methods. |
| `createProductReview(input: CreateProductReviewInput!)` | `CreateProductReviewOutput!` | Create a product review for the specified product. |
| `deleteCompareList(uid: ID!)` | `DeleteCompareListOutput` | Delete the specified compare list. |
| `deleteCustomer` | `Boolean` | Delete customer account |
| `deleteCustomerAddressV2(uid: ID!)` | `Boolean` | Delete the billing or shipping address of a customer. |
| `deletePaymentToken(public_hash: String!)` | `DeletePaymentTokenOutput` | Delete a customer's payment token. |
| `estimateShippingMethods(input: EstimateTotalsInput!)` | `[AvailableShippingMethod]` | Estimate shipping method(s) for cart based on address |
| `estimateTotals(input: EstimateTotalsInput!)` | `EstimateTotalsOutput!` | Estimate totals for cart based on the address |
| `generateCustomerToken(email: String!, password: String!)` | `CustomerToken` | Generate a token for specified customer. |
| `generateCustomerTokenAsAdmin(input: GenerateCustomerTokenAsAdminInput!)` | `GenerateCustomerTokenAsAdminOutput` | Request a customer token so that an administrator can perform remote shopping assistance. |
| `handlePayflowProResponse(input: PayflowProResponseInput!)` | `PayflowProResponseOutput` | Handle a payment response and save the payment in Quote. Use this mutation for Payflow Pro and Payments Pro payment methods. |
| `mergeCarts(source_cart_id: String!, destination_cart_id: String)` | `Cart!` | Transfer the contents of a guest cart into the cart of a logged-in customer. |
| `placeOrder(input: PlaceOrderInput)` | `PlaceOrderOutput` | Convert the quote into an order. |
| `removeCouponFromCart(input: RemoveCouponFromCartInput)` | `RemoveCouponFromCartOutput` | Remove a previously-applied coupon from the cart. The cart must contain at least one item in order to remove the coupon. |
| `removeItemFromCart(input: RemoveItemFromCartInput)` | `RemoveItemFromCartOutput` | Delete the entire quantity of a specified item from the cart. If you remove all items from the cart, the cart continues to exist. |
| `removeProductsFromCompareList(input: RemoveProductsFromCompareListInput)` | `CompareList` | Remove products from the specified compare list. |
| `removeProductsFromWishlist(wishlistId: ID!, wishlistItemsIds: [ID!]!)` | `RemoveProductsFromWishlistOutput` | Remove one or more products from the specified wish list. |
| `reorderItems(orderNumber: String!)` | `ReorderItemsOutput` | Add all products from a customer's previous order to the cart. |
| `requestGuestOrderCancel(input: GuestOrderCancelInput!)` | `CancelOrderOutput` | Request to cancel specified guest order. |
| `requestPasswordResetEmail(email: String!)` | `Boolean` | Request an email with a reset password token for the registered customer identified by the specified email. |
| `resendConfirmationEmail(email: String!)` | `Boolean` | Resends the confirmation email to a customer. |
| `resetPassword(email: String!, resetPasswordToken: String!, newPassword: String!)` | `Boolean` | Reset a customer's password using the reset password token that the customer received in an email after requesting it using `requestPasswordResetEmail`. |
| `revokeCustomerToken` | `RevokeCustomerTokenOutput` | Revoke the customer token. |
| `sendEmailToFriend(input: SendEmailToFriendInput)` | `SendEmailToFriendOutput` | Send a message on behalf of a customer to the specified email addresses. |
| `setBillingAddressOnCart(input: SetBillingAddressOnCartInput)` | `SetBillingAddressOnCartOutput` | Set the billing address on a specific cart. |
| `setGuestEmailOnCart(input: SetGuestEmailOnCartInput)` | `SetGuestEmailOnCartOutput` | Assign the email address of a guest to the cart. |
| `setPaymentMethodOnCart(input: SetPaymentMethodOnCartInput)` | `SetPaymentMethodOnCartOutput` | Apply a payment method to the cart. |
| `setShippingAddressesOnCart(input: SetShippingAddressesOnCartInput)` | `SetShippingAddressesOnCartOutput` | Set one or more shipping addresses on a specific cart. |
| `setShippingMethodsOnCart(input: SetShippingMethodsOnCartInput)` | `SetShippingMethodsOnCartOutput` | Set one or more delivery methods on a cart. |
| `subscribeEmailToNewsletter(email: String!)` | `SubscribeEmailToNewsletterOutput` | Subscribe the specified email to the store's newsletter. |
| `updateCartItems(input: UpdateCartItemsInput)` | `UpdateCartItemsOutput` | Modify items in the cart. |
| `updateCustomerAddressV2(uid: ID!, input: CustomerAddressInput)` | `CustomerAddress` | Update the billing or shipping address of a customer or guest. |
| `updateCustomerEmail(email: String!, password: String!)` | `CustomerOutput` | Change the email address for the logged-in customer. |
| `updateCustomerV2(input: CustomerUpdateInput!)` | `CustomerOutput` | Update the customer's personal information. |
| `updateProductsInWishlist(wishlistId: ID!, wishlistItems: [WishlistItemUpdateInput!]!)` | `UpdateProductsInWishlistOutput` | Update one or more products in the specified wish list. |
