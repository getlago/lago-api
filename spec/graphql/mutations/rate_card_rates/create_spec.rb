# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::RateCardRates::Create do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input:}
    )
  end

  let(:required_permission) { "rate_cards:create" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:rate_card) { create(:rate_card, organization:) }

  let(:input) do
    {
      code: "gql_rate", rateCardId: rate_card.id,
      effectiveFrom: 1.month.from_now.beginning_of_day.iso8601,
      rateModel: "standard",
      rateProperties: {amount: "10"},
      billingIntervalUnit: "month"
    }
  end

  let(:mutation) do
    <<-GQL
      mutation($input: CreateRateCardRateInput!) {
        createRateCardRate(input: $input) {
          id status rateModel billingIntervalUnit
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "rate_cards:create"

  it "adds a pending rate to the card" do
    result_data = execution["data"]["createRateCardRate"]

    expect(result_data["id"]).to be_present
    expect(result_data["status"]).to eq("pending")
    expect(result_data["rateModel"]).to eq("standard")
  end

  context "with graduated tiers" do
    let(:input) do
      super().merge(
        rateModel: "graduated",
        rateProperties: {
          graduatedRanges: [
            {toValue: "10", flatAmount: "0", perUnitAmount: "1"},
            {toValue: nil, flatAmount: "0", perUnitAmount: "0.5"}
          ]
        }
      )
    end

    let(:mutation) do
      <<-GQL
        mutation($input: CreateRateCardRateInput!) {
          createRateCardRate(input: $input) {
            id rateProperties { graduatedRanges { toValue flatAmount perUnitAmount } }
          }
        }
      GQL
    end

    it "takes and returns tiers by their upper bound" do
      ranges = execution["data"]["createRateCardRate"]["rateProperties"]["graduatedRanges"]

      expect(ranges.map { it["toValue"] }).to eq(["10", nil])
    end
  end

  context "when the rate card belongs to another organization" do
    let(:rate_card) { create(:rate_card) }

    it "returns a not found error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end
end
