# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::RateCardResolver do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {rateCardId: rate_card.id}
    )
  end

  let(:required_permission) { "rate_cards:view" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:rate_card) { create(:rate_card, organization:) }

  let(:query) do
    <<~GQL
      query($rateCardId: ID!) {
        rateCard(id: $rateCardId) {
          id name code currency
          rates { id status }
        }
      }
    GQL
  end

  before { create(:rate_card_rate, organization:, rate_card:) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "rate_cards:view"

  it "returns a single rate card with its rates" do
    response = execution["data"]["rateCard"]

    expect(response["id"]).to eq(rate_card.id)
    expect(response["rates"].count).to eq(1)
  end

  context "when the rate card belongs to another organization" do
    let(:rate_card) { create(:rate_card) }

    it "returns a not found error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end
end
