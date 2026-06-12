# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::RateCardRates::Update do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input:}
    )
  end

  let(:required_permission) { "rate_cards:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:rate_card_rate) do
    create(:rate_card_rate, organization:, rate_card:, effective_datetime: 1.month.from_now)
  end

  let(:input) { {id: rate_card_rate.id, rateProperties: {amount: "25"}} }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateRateCardRateInput!) {
        updateRateCardRate(input: $input) {
          id rateProperties status
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "rate_cards:update"

  it "updates the rate" do
    result_data = execution["data"]["updateRateCardRate"]

    expect(result_data["id"]).to eq(rate_card_rate.id)
    expect(result_data["rateProperties"]).to eq("amount" => "25")
  end

  context "when the rate belongs to another organization" do
    let(:rate_card_rate) { create(:rate_card_rate) }

    it "returns a not found error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end
end
