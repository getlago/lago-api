# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::PaymentMethodsResolver do
  let(:required_permission) { "payment_methods:view" }

  let(:payment_method) { create(:payment_method, customer:, organization:) }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }

  before do
    payment_method
    create(:payment_method, organization:)
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "payment_methods:view"

  context "when external customer id is present" do
    let(:query) do
      <<~GQL
        query($externalCustomerId: ID!) {
          paymentMethods(externalCustomerId: $externalCustomerId, limit: 5) {
            collection {
              id
              customer { id }
              isDefault
              paymentProviderCode
              paymentProviderType
            }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    it "returns a list of payment methods", :aggregate_failures do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {
          externalCustomerId: customer.external_id
        }
      )

      payments_response = result["data"]["paymentMethods"]

      expect(payments_response["collection"].count).to eq(1)
      expect(payments_response["collection"].first["paymentProviderCode"]).to eq(payment_method.payment_provider.code)
      expect(payments_response["collection"].first["paymentProviderType"]).to eq("stripe")
    end
  end
end
