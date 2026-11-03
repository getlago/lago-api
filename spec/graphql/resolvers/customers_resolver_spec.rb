# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::CustomersResolver do
  let(:required_permission) { "customers:view" }
  let(:organization) { membership.organization }
  let(:billing_entity1) { organization.default_billing_entity }
  let(:query) do
    <<~GQL
      query(
        $searchTerm: String,
        $page: Int,
        $limit: Int,
        $accountType: [CustomerAccountTypeEnum!],
        $billingEntityIds: [ID!],
        $activeSubscriptionsCountFrom: Int,
        $activeSubscriptionsCountTo: Int,
        $customerType: CustomerTypeEnum,
        $externalId: String,
        $hasCustomerType: Boolean,
        $hasTaxIdentificationNumber: Boolean,
        $countries: [CountryCode!],
        $states: [String!],
        $zipcodes: [String!],
        $currencies: [CurrencyEnum!],
        $withDeleted: Boolean,
        $metadata: [CustomerMetadataFilter!]
      ) {
        customers(
          limit: $limit,
          searchTerm: $searchTerm,
          page: $page,
          accountType: $accountType,
          billingEntityIds: $billingEntityIds,
          activeSubscriptionsCountFrom: $activeSubscriptionsCountFrom,
          activeSubscriptionsCountTo: $activeSubscriptionsCountTo,
          customerType: $customerType,
          externalId: $externalId,
          hasCustomerType: $hasCustomerType,
          hasTaxIdentificationNumber: $hasTaxIdentificationNumber,
          countries: $countries,
          states: $states,
          zipcodes: $zipcodes,
          currencies: $currencies,
          withDeleted: $withDeleted,
          metadata: $metadata
        ) {
          collection { id externalId name }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:membership) { create_default(:membership) }
  let_it_be(:billing_entity2) { create_default(:billing_entity, organization:) }

  def test_customers_resolver(expected_customers, variables: {})
    variables = {page: 1, limit: 5}.merge(variables)
    result = execute_query(query:, variables: variables)

    customers_response = result["data"]["customers"]

    expected_customers = Array.wrap(expected_customers)

    expect(customers_response["collection"].count).to eq(expected_customers.count)
    expect(customers_response["collection"].pluck("id")).to match_array(expected_customers.pluck(:id))

    expect(customers_response["metadata"]["currentPage"]).to eq(1)
    expect(customers_response["metadata"]["totalCount"]).to eq(expected_customers.count)
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "customers:view"

  it "returns a list of customers" do
    customer_1 = create(:customer, organization:)
    customer_2 = create(:customer, organization:)

    test_customers_resolver([customer_1, customer_2])
  end

  context "without current organization" do
    it "returns an error" do
      result = execute_graphql(current_user: membership.user, query:)

      expect_graphql_error(result:, message: "Missing organization id")
    end
  end

  context "when filtering by external id" do
    let(:customer) { create(:customer, organization:) }

    before do
      customer
    end

    it "returns the customer with matching external_id" do
      test_customers_resolver(customer, variables: {externalId: customer.external_id})
    end
  end

  context "when filtering by partner account type" do
    let(:customer) { create(:customer, organization:) }
    let(:partner) { create(:customer, organization:, account_type: "partner") }

    before do
      customer
      partner
    end

    it "returns all customers with account_type partner" do
      test_customers_resolver(partner, variables: {accountType: ["partner"]})
    end
  end

  context "when filtering by billing_entity_id" do
    let(:customer) { create(:customer, organization:, billing_entity: billing_entity1) }
    let(:customer2) { create(:customer, organization:, billing_entity: billing_entity2) }

    before do
      customer
      customer2
    end

    it "returns all customers for the specified billing entity" do
      test_customers_resolver(customer2, variables: {billingEntityIds: [billing_entity2.id]})
    end
  end

  context "when filtering by with_deleted" do
    let(:customer) { create(:customer, organization:) }
    let(:deleted_customer) { create(:customer, organization:, deleted_at: Time.current) }

    before do
      customer
      deleted_customer
    end

    it "returns all customers including deleted ones" do
      test_customers_resolver([customer, deleted_customer], variables: {withDeleted: true})
    end
  end

  context "when filtering by active subscriptions" do
    let(:active_subscription_customer) { create(:customer, organization:) }

    before do
      other_customer = create(:customer, organization:)
      create(:subscription, customer: other_customer)
      2.times do
        create(:subscription, customer: active_subscription_customer)
      end
    end

    it "returns all customers with 2 active subscriptions" do
      test_customers_resolver(active_subscription_customer, variables: {activeSubscriptionsCountFrom: 2, activeSubscriptionsCountTo: 2})
    end
  end

  context "when filtering by customer_type" do
    let!(:company_customer) { create(:customer, organization:, customer_type: "company") }

    before do
      create(:customer, organization:, customer_type: "individual")
    end

    it "returns all customers with customer_type company" do
      test_customers_resolver(company_customer, variables: {customerType: "company"})
    end
  end

  context "when filtering by has_customer_type" do
    let!(:company_customer) { create(:customer, organization:, customer_type: "company") }

    before do
      create(:customer, organization:, customer_type: nil)
    end

    it "returns all customers with customer_type company" do
      test_customers_resolver(company_customer, variables: {hasCustomerType: true})
    end
  end

  context "when filtering by has_tax_identification_number" do
    let!(:customer_with_tax_identification_number) { create(:customer, organization:, tax_identification_number: "1234567890") }

    before do
      create(:customer, organization:, tax_identification_number: nil)
    end

    it "returns all customers with tax_identification_number" do
      test_customers_resolver(customer_with_tax_identification_number, variables: {hasTaxIdentificationNumber: true})
    end
  end

  context "when filtering by countries" do
    let!(:customer_in_france) { create(:customer, organization:, country: "FR") }

    before do
      create(:customer, organization:, country: "US")
    end

    it "returns all customers in France" do
      test_customers_resolver(customer_in_france, variables: {countries: ["FR"]})
    end
  end

  context "when filtering by states" do
    let!(:customer_in_new_york) { create(:customer, organization:, state: "NY") }

    before do
      create(:customer, organization:, state: "CA")
    end

    it "returns all customers in New York" do
      test_customers_resolver(customer_in_new_york, variables: {states: ["NY"]})
    end
  end

  context "when filtering by zipcodes" do
    let!(:customer_in_new_york) { create(:customer, organization:, zipcode: "10001") }

    before do
      create(:customer, organization:, zipcode: "90001")
    end

    it "returns all customers in New York" do
      test_customers_resolver(customer_in_new_york, variables: {zipcodes: ["10001"]})
    end
  end

  context "when filtering by currencies" do
    let!(:customer_in_usd) { create(:customer, organization:, currency: "USD") }

    before do
      create(:customer, organization:, currency: "EUR")
    end

    it "returns all customers in USD" do
      test_customers_resolver(customer_in_usd, variables: {currencies: ["USD"]})
    end
  end

  context "when filtering by search_term" do
    let(:john_doe) { create(:customer, organization:, name: "John, Doe", email: "john@doe.com", legal_name: "John-Doe", firstname: "Johnnas", lastname: "Doefe", external_id: "1234567890") }

    before do
      create(:customer, organization:, name: "Jane Doe", email: "jane@doe.com", legal_name: "Jane-Doe", firstname: "Janenas", lastname: "Doefae", external_id: "1234567891")
    end

    [
      ["John,", :name],
      ["ohn@doe.com", :email],
      ["hn-d", :legal_name],
      ["nnas", :firstname],
      ["doefe", :lastname],
      ["1234567890", :external_id]
    ].each do |search_term, field|
      context "when search_term matches #{field}" do
        it "returns the matching customer" do
          test_customers_resolver(john_doe, variables: {searchTerm: search_term})
        end
      end
    end
  end

  context "when filtering by metadata" do
    let!(:customer_with_metadata) { create(:customer, organization:) }

    before do
      create(:customer_metadata, customer: customer_with_metadata, key: "key_1", value: "value_1")

      second_customer = create(:customer, organization:)
      create(:customer_metadata, customer: second_customer, key: "key_1", value: "value_1")
      create(:customer_metadata, customer: second_customer, key: "key_2", value: "value_2")
    end

    it "returns all customers with metadata" do
      test_customers_resolver(
        customer_with_metadata,
        variables: {metadata: [{key: "key_1", value: "value_1"}, {key: "key_2", value: ""}]}
      )
    end

    context "with the capped count metadata" do
      let(:query) do
        <<~GQL
          query($metadata: [CustomerMetadataFilter!]) {
            customers(page: 1, limit: 1, metadata: $metadata) {
              collection { id }
              metadata { totalCount totalCountCapped hasNextPage }
            }
          }
        GQL
      end

      let(:metadata_filter) { [{key: "key_1", value: "value_1"}, {key: "key_2", value: ""}] }
      let(:metadata) { execute_query(query:, variables: {metadata: metadata_filter}).dig("data", "customers", "metadata") }

      it "counts only the matching customers" do
        expect(metadata).to eq(
          "totalCount" => 1, # customer_with_metadata, the second customer has key_2
          "totalCountCapped" => false,
          "hasNextPage" => false
        )
      end

      context "when both customers match and exceed the cap" do
        let(:metadata_filter) { [{key: "key_1", value: "value_1"}] }

        before { stub_const("BaseQuery::CappedTotalCount::MAX_COUNTED_RECORDS", 1) }

        it "caps the total count" do
          expect(metadata).to eq(
            "totalCount" => 1, # the stubbed cap, not the 2 customers with key_1
            "totalCountCapped" => true,
            "hasNextPage" => true
          )
        end
      end
    end
  end

  describe "total count" do
    let(:page) { 1 }
    let(:metadata_fields) { "currentPage totalCount totalPages totalCountCapped hasNextPage" }
    let(:query) do
      <<~GQL
        query {
          customers(page: #{page}, limit: 1) {
            collection { id }
            metadata { #{metadata_fields} }
          }
        }
      GQL
    end

    let(:result) { execute_query(query:) }
    let(:metadata) { result.dig("data", "customers", "metadata") }

    before do
      stub_const("BaseQuery::CappedTotalCount::MAX_COUNTED_RECORDS", 3)
      create_list(:customer, 2, organization:)
    end

    it "returns the exact total and advertises the next page" do
      expect(metadata).to eq(
        "currentPage" => 1,
        "totalCount" => 2, # the 2 customers, below the cap of 3
        "totalPages" => 2, # ceil(2 / 1)
        "totalCountCapped" => false,
        "hasNextPage" => true
      )
    end

    it "does not count customers of another organization" do
      create(:customer, organization: create(:organization))

      expect(metadata).to eq(
        "currentPage" => 1,
        "totalCount" => 2, # the 2 customers of the organization, not the other one's
        "totalPages" => 2, # ceil(2 / 1)
        "totalCountCapped" => false,
        "hasNextPage" => true
      )
    end

    context "when the result set exceeds the cap" do
      before { stub_const("BaseQuery::CappedTotalCount::MAX_COUNTED_RECORDS", 1) }

      it "caps the total and keeps advertising the next page" do
        expect(metadata).to eq(
          "currentPage" => 1,
          "totalCount" => 1, # the stubbed cap, not the 2 customers
          "totalPages" => 1, # ceil(1 / 1)
          "totalCountCapped" => true,
          "hasNextPage" => true
        )
      end

      context "when the app selects only the current metadata fields" do
        let(:metadata_fields) { "currentPage totalCount totalPages" }

        it "limits the count query to the cap" do
          count_queries = []
          callback = lambda do |*, payload|
            count_queries << payload[:sql] if payload[:sql].match?(/SELECT COUNT/i) && payload[:sql].include?('"customers"')
          end
          ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { result }

          expect(metadata).to eq(
            "currentPage" => 1,
            "totalCount" => 1, # the stubbed cap, not the 2 customers
            "totalPages" => 1 # ceil(1 / 1)
          )
          expect(count_queries).not_to be_empty
          expect(count_queries).to all(include("LIMIT"))
        end
      end

      context "when on the last page" do
        let(:page) { 2 }

        it "reports no next page" do
          expect(metadata).to include("totalCountCapped" => true, "hasNextPage" => false)
        end
      end
    end

    context "when the results land exactly on the cap" do
      before { stub_const("BaseQuery::CappedTotalCount::MAX_COUNTED_RECORDS", 2) }

      it "reports the total as exact" do
        expect(metadata).to eq(
          "currentPage" => 1,
          "totalCount" => 2, # the 2 customers, equal to the cap
          "totalPages" => 2, # ceil(2 / 1)
          "totalCountCapped" => false,
          "hasNextPage" => true
        )
      end

      context "when on the last page" do
        let(:page) { 2 }

        it "reports no next page" do
          expect(metadata).to include("totalCountCapped" => false, "hasNextPage" => false)
        end
      end

      context "when past the last page" do
        let(:page) { 3 }

        it "reports no next page" do
          expect(result.dig("data", "customers", "collection")).to eq([])
          expect(metadata).to include("hasNextPage" => false)
        end
      end
    end
  end

  context "when a filter is refused by the query contract" do
    let(:query) do
      <<~GQL
        query($billingEntityIds: [ID!]) {
          customers(page: 1, limit: 5, billingEntityIds: $billingEntityIds) {
            collection { id }
            metadata { currentPage totalCount }
          }
        }
      GQL
    end

    let(:result) { execute_query(query:, variables: {billingEntityIds: ["not-a-uuid"]}) }

    it "returns a validation error" do
      expect(result["data"]).to be_nil
      expect_graphql_error(result:, message: "Unprocessable Entity", details: {billingEntityIds: {0 => ["is in invalid format"]}})
    end
  end

  context "with N+1 query detection on associations", bullet: {unused_eager_loading: false} do
    let(:query) do
      <<~GQL
        query(
          $searchTerm: String,
          $page: Int,
          $limit: Int,
          $accountType: [CustomerAccountTypeEnum!],
          $billingEntityIds: [ID!],
          $activeSubscriptionsCountFrom: Int,
          $activeSubscriptionsCountTo: Int,
          $customerType: CustomerTypeEnum,
          $hasCustomerType: Boolean,
          $hasTaxIdentificationNumber: Boolean,
          $countries: [CountryCode!],
          $states: [String!],
          $zipcodes: [String!],
          $currencies: [CurrencyEnum!],
          $withDeleted: Boolean,
          $metadata: [CustomerMetadataFilter!]
        ) {
          customers(
            limit: $limit,
            searchTerm: $searchTerm,
            page: $page,
            accountType: $accountType,
            billingEntityIds: $billingEntityIds,
            activeSubscriptionsCountFrom: $activeSubscriptionsCountFrom,
            activeSubscriptionsCountTo: $activeSubscriptionsCountTo,
            customerType: $customerType,
            hasCustomerType: $hasCustomerType,
            hasTaxIdentificationNumber: $hasTaxIdentificationNumber,
            countries: $countries,
            states: $states,
            zipcodes: $zipcodes,
            currencies: $currencies,
            withDeleted: $withDeleted,
            metadata: $metadata
          ) {
            collection {
              id
              activeSubscriptionsCount
              shippingAddress {
                addressLine1
                addressLine2
                city
                country
                state
                zipcode
              }
              metadata {
                id
                key
                value
                displayInInvoice
              }
              billingEntity {
                id
                code
                name
              }
              netsuiteCustomer {
                id
                integrationId
                externalCustomerId
                integrationCode
                integrationType
                subsidiaryId
                syncWithProvider
              }
              anrokCustomer {
                id
                integrationId
                externalCustomerId
                integrationCode
                integrationType
                syncWithProvider
              }
              avalaraCustomer {
                id
                integrationId
                externalCustomerId
                integrationCode
                integrationType
                syncWithProvider
              }
              xeroCustomer {
                id
                integrationId
                externalCustomerId
                integrationCode
                integrationType
                syncWithProvider
              }
              hubspotCustomer {
                id
                integrationId
                externalCustomerId
                integrationCode
                integrationType
                syncWithProvider
                targetedObject
              }
              salesforceCustomer {
                id
                integrationId
                externalCustomerId
                integrationCode
                integrationType
                syncWithProvider
              }
              providerCustomer {
                id
                providerCustomerId
                syncWithProvider
                providerPaymentMethods
              }
            }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    before do
      create(:customer, organization:, billing_entity: billing_entity1)
      create(:customer, organization:, billing_entity: billing_entity2)
    end

    it "does not trigger N+1 queries on associations" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      expect(result["data"]["customers"]["collection"].count).to eq(2)
    end
  end
end
