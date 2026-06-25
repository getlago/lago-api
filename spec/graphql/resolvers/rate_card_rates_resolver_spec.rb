# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::RateCardRatesResolver do
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
  let!(:rate) { create(:rate_card_rate, organization:, rate_card:) }

  let(:query) do
    <<~GQL
      query($rateCardId: ID!) {
        rateCardRates(rateCardId: $rateCardId, limit: 5) {
          collection { id status }
          metadata { totalCount }
        }
      }
    GQL
  end

  before { create(:rate_card_rate, organization:) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "rate_cards:view"

  it "returns the rates of the rate card" do
    rates = execution["data"]["rateCardRates"]

    expect(rates["collection"].map { it["id"] }).to eq([rate.id])
    expect(rates["metadata"]["totalCount"]).to eq(1)
  end
end
