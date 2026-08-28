# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Payments::Create do
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query: mutation,
      variables: {input:}
    )
  end

  let(:required_permission) { "payments:create" }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, organization:, total_amount_cents: 100) }
  let(:input) do
    {
      invoiceId: invoice.id,
      reference: "ref1",
      amountCents: 100,
      createdAt: 1.day.ago.iso8601
    }
  end
  let(:mutation) do
    <<-GQL
      mutation($input: CreatePaymentInput!) {
        createPayment(input: $input) {
          id
          payablePaymentStatus
          paymentType
        }
      }
    GQL
  end

  let_it_be(:customer) { create_default(:customer) }
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:membership) { create_default(:membership) }

  context "with premium organization", :premium do
    it "creates a manual payment" do
      expect(result["data"]).to include(
        "createPayment" => {
          "id" => anything,
          "payablePaymentStatus" => "succeeded",
          "paymentType" => "manual"
        }
      )
    end
  end

  context "with free organization" do
    it "returns an error" do
      expect_graphql_error(result:, message: "feature_unavailable")
    end
  end
end
