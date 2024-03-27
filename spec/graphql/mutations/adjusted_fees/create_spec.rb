# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::AdjustedFees::Create, type: :graphql do
  around { |test| lago_premium!(&test) }

  let(:membership) { create(:membership) }
  let(:fee) { create(:charge_fee) }
  let(:input) do
    {
      feeId: fee.id,
      units: 4,
      unitAmountCents: 1000,
      invoiceDisplayName: "Hello"
    }
  end

  let(:mutation) do
    <<-GQL
      mutation($input: CreateAdjustedFeeInput!) {
        createAdjustedFee(input: $input) {
          id,
          units,
          invoiceDisplayName
        }
      }
    GQL
  end

  before { fee.invoice.draft! }

  it "creates an adjusted fee" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      query: mutation,
      variables: {input:}
    )

    expect(result["data"]["createAdjustedFee"]["id"]).to eq(fee.id)
  end

  context "with finalized invoice" do
    before { fee.invoice.finalized! }

    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        query: mutation,
        variables: {input:}
      )

      expect_forbidden_error(result)
    end
  end

  context "without current user" do
    it "returns an error" do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {input:}
      )

      expect_unauthorized_error(result)
    end
  end

  context "without current organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        query: mutation,
        variables: {input:}
      )

      expect_forbidden_error(result)
    end
  end
end
