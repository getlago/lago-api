# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::RateCardRateResolver do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {rateId: rate.id}
    )
  end

  let(:required_permission) { "rate_cards:view" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:rate) { create(:rate_card_rate, organization:, rate_card:) }

  let(:query) do
    <<~GQL
      query($rateId: ID!) {
        rateCardRate(id: $rateId) {
          id code rateModel status
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "rate_cards:view"

  it "returns a single rate" do
    response = execution["data"]["rateCardRate"]

    expect(response["id"]).to eq(rate.id)
    expect(response["code"]).to eq(rate.code)
  end

  context "when the rate belongs to another organization" do
    let(:rate) { create(:rate_card_rate) }

    it "returns a not found error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end
end
