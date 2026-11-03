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
  let!(:rate) { create(:rate_card_rate, organization:, rate_card:) }
  let!(:pending_rate) { create(:rate_card_rate, organization:, rate_card:, code: "pending", effective_from: 1.month.from_now.beginning_of_day) }

  let(:query) do
    <<~GQL
      query($rateCardId: ID!) {
        rateCard(id: $rateCardId) {
          id name code currency
          ratesCount
          activeRate { id }
          nextPendingRate { id }
          taxes { id code rate }
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "rate_cards:view"

  it "returns a single rate card with its rates count, active rate, pending rate, and taxes" do
    tax = create(:tax, organization:)
    create(:rate_card_applied_tax, rate_card:, tax:, organization:)

    response = execution["data"]["rateCard"]

    expect(response["id"]).to eq(rate_card.id)
    expect(response["ratesCount"]).to eq(2)
    expect(response["activeRate"]["id"]).to eq(rate.id)
    expect(response["nextPendingRate"]["id"]).to eq(pending_rate.id)
    expect(response["taxes"].pluck("code")).to eq([tax.code])
  end

  context "when the rate card belongs to another organization" do
    let(:rate_card) { create(:rate_card) }

    it "returns a not found error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end

  context "with an explicit asOf perspective on nextPendingRate" do
    subject(:execution) do
      execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {rateCardId: rate_card.id, asOf: as_of}
      )
    end

    let(:rate_card) { create(:rate_card, organization:) }
    let!(:rate) { nil }
    let!(:pending_rate) { nil }
    let!(:nov_1) { create(:rate_card_rate, organization:, rate_card:, code: "nov-1", effective_from: Time.zone.parse("2026-11-01")) }
    let!(:nov_16) { create(:rate_card_rate, organization:, rate_card:, code: "nov-16", effective_from: Time.zone.parse("2026-11-16")) }

    let(:query) do
      <<~GQL
        query($rateCardId: ID!, $asOf: ISO8601DateTime) {
          rateCard(id: $rateCardId) {
            id
            nextPendingRate(asOf: $asOf) { id }
          }
        }
      GQL
    end

    context "when opened before November" do
      let(:as_of) { "2026-10-30T00:00:00Z" }

      it "resolves Nov 1st as the soonest pending rate" do
        expect(execution["data"]["rateCard"]["nextPendingRate"]["id"]).to eq(nov_1.id)
      end
    end

    context "when opened mid-November" do
      let(:as_of) { "2026-11-15T00:00:00Z" }

      it "skips the already-effective Nov 1st rate and resolves Nov 16th" do
        expect(execution["data"]["rateCard"]["nextPendingRate"]["id"]).to eq(nov_16.id)
      end
    end
  end
end
