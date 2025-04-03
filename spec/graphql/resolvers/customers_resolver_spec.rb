# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::CustomersResolver, type: :graphql do
  let(:required_permission) { "customers:view" }
  let(:query) do
    <<~GQL
      query {
        customers(limit: 5) {
          collection { id externalId name }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:billing_entity1) { organization.default_billing_entity }
  let(:billing_entity2) { create(:billing_entity, organization:) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "customers:view"

  it "returns a list of customers" do
    customer = create(:customer, organization:)

    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:
    )

    customers_response = result["data"]["customers"]

    aggregate_failures do
      expect(customers_response["collection"].count).to eq(organization.customers.count)
      expect(customers_response["collection"].first["id"]).to eq(customer.id)

      expect(customers_response["metadata"]["currentPage"]).to eq(1)
      expect(customers_response["metadata"]["totalCount"]).to eq(1)
    end
  end

  context "without current organization" do
    it "returns an error" do
      result = execute_graphql(current_user: membership.user, query:)

      expect_graphql_error(
        result:,
        message: "Missing organization id"
      )
    end
  end

  context "when filtering by partner account type" do
    let(:customer) { create(:customer, organization:) }
    let(:partner) { create(:customer, organization:, account_type: "partner") }

    let(:query) do
      <<~GQL
        query($accountType: [CustomerAccountTypeEnum!]) {
          customers(limit: 5, accountType: $accountType) {
            collection { id }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    before do
      customer
      partner
    end

    it "returns all customers with account_type partner" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {accountType: "partner"}
      )

      invoices_response = result["data"]["customers"]

      expect(invoices_response["collection"].count).to eq(1)
      expect(invoices_response["collection"].first["id"]).to eq(partner.id)

      expect(invoices_response["metadata"]["currentPage"]).to eq(1)
      expect(invoices_response["metadata"]["totalCount"]).to eq(1)
    end
  end

  context "when filtering by billing_entity_id" do
    let(:customer) { create(:customer, organization:, billing_entity: billing_entity1) }
    let(:customer2) { create(:customer, organization:, billing_entity: billing_entity2) }

    let(:query) do
      <<~GQL
        query($billingEntityIds: [ID!]) {
          customers(limit: 5, billingEntityIds: $billingEntityIds) {
            collection { id }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    before do
      customer
      customer2
    end

    it "returns all customers for the specified billing entity" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {billingEntityIds: [billing_entity2.id]}
      )

      customers_response = result["data"]["customers"]

      expect(customers_response["collection"].count).to eq(1)
      expect(customers_response["collection"].first["id"]).to eq(customer2.id)

      expect(customers_response["metadata"]["currentPage"]).to eq(1)
      expect(customers_response["metadata"]["totalCount"]).to eq(1)
    end
  end

  context "when filtering by with_deleted" do
    let(:customer) { create(:customer, organization:) }
    let(:deleted_customer) { create(:customer, organization:, deleted_at: Time.current) }

    let(:query) do
      <<~GQL
        query($withDeleted: Boolean) {
          customers(limit: 5, withDeleted: $withDeleted) {
            collection { id }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    before do
      customer
      deleted_customer
    end

    it "returns all customers including deleted ones" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {withDeleted: true}
      )

      customers_response = result["data"]["customers"]

      expect(customers_response["collection"].count).to eq(2)
      expect(customers_response["collection"].map { |c| c["id"] }).to include(customer.id, deleted_customer.id)

      expect(customers_response["metadata"]["currentPage"]).to eq(1)
      expect(customers_response["metadata"]["totalCount"]).to eq(2)
    end
  end
end
