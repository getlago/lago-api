# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::PaymentProviderCustomers::SetAsDefault do
  let(:required_permission) { "customers:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:user) { membership.user }

  let(:stripe_customer) { create(:stripe_customer, customer:, organization:, code: "stripe_eu", is_default: true) }
  let(:gocardless_customer) { create(:gocardless_customer, customer:, organization:, code: "gocardless_eu", is_default: false) }

  let(:mutation) do
    <<-GQL
      mutation($input: SetPaymentProviderCustomerAsDefaultInput!) {
        setPaymentProviderCustomerAsDefault(input: $input) {
          id
          code
          isDefault
        }
      }
    GQL
  end

  before do
    stripe_customer
    gocardless_customer
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "customers:update"

  context "with valid preconditions" do
    it "sets the connection as default and returns it" do
      result = execute_graphql(
        current_organization: organization,
        current_user: user,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {id: gocardless_customer.id}
        }
      )

      data = result["data"]["setPaymentProviderCustomerAsDefault"]

      expect(data["id"]).to eq(gocardless_customer.id)
      expect(data["code"]).to eq("gocardless_eu")
      expect(data["isDefault"]).to be(true)
      expect(gocardless_customer.reload.is_default).to be(true)
      expect(stripe_customer.reload.is_default).to be(false)
    end
  end

  context "when the connection belongs to another organization" do
    let(:other_customer) { create(:customer) }
    let(:other_connection) do
      create(:stripe_customer, customer: other_customer, organization: other_customer.organization, code: "stripe_eu")
    end

    it "returns an error" do
      result = execute_graphql(
        current_organization: organization,
        current_user: user,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {id: other_connection.id}
        }
      )

      expect_not_found(result)
    end
  end

  context "when the connection is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_organization: organization,
        current_user: user,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {id: SecureRandom.uuid}
        }
      )

      expect_not_found(result)
    end
  end
end
