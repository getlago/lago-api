# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::RateCardRates::Destroy do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input: {id: rate_card_rate.id}}
    )
  end

  let(:required_permission) { "rate_cards:delete" }
  let(:organization) { membership.organization }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:rate_card_rate) do
    create(:rate_card_rate, organization:, rate_card:, effective_from: 1.month.from_now.beginning_of_day)
  end
  let(:mutation) do
    <<-GQL
      mutation($input: DestroyRateCardRateInput!) {
        destroyRateCardRate(input: $input) { id }
      }
    GQL
  end

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:billable_metric) { create_default(:billable_metric) }
  let_it_be(:membership) { create_default(:membership) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "rate_cards:delete"

  it "soft deletes the pending rate" do
    expect(execution["data"]["destroyRateCardRate"]["id"]).to eq(rate_card_rate.id)
    expect(rate_card_rate.reload).to be_discarded
  end

  context "with an active rate" do
    let(:rate_card_rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_from: 1.month.ago.beginning_of_day)
    end

    it "returns a validation error" do
      expect_graphql_error(result: execution, message: :unprocessable_entity)
    end
  end
end
