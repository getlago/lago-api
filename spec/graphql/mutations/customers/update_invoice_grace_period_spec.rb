# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Customers::UpdateInvoiceGracePeriod do
  let(:required_permissions) { "customer_settings:update:grace_period" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }

  let(:mutation) do
    <<~GQL
      mutation($input: UpdateCustomerInvoiceGracePeriodInput!) {
        updateCustomerInvoiceGracePeriod(input: $input) {
          id,
          name,
          externalId,
          invoiceGracePeriod
        }
      }
    GQL
  end

  around { |test| lago_premium!(&test) }

  it_behaves_like "requires current user"
  it_behaves_like "requires permission", %w[customers:update customer_settings:update:grace_period]

  it "updates a customer" do
    result = execute_graphql(
      current_user: membership.user,
      permissions: required_permissions,
      query: mutation,
      variables: {
        input: {
          id: customer.id,
          invoiceGracePeriod: 12
        }
      }
    )

    result_data = result["data"]["updateCustomerInvoiceGracePeriod"]

    aggregate_failures do
      expect(result_data["id"]).to be_present
      expect(result_data["invoiceGracePeriod"]).to eq(12)
    end
  end
end
