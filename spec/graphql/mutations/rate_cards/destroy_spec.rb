# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::RateCards::Destroy do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input: {id: rate_card.id}}
    )
  end

  let(:required_permission) { "rate_cards:delete" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:rate_card) { create(:rate_card, organization:) }

  let(:mutation) do
    <<-GQL
      mutation($input: DestroyRateCardInput!) {
        destroyRateCard(input: $input) { id }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "rate_cards:delete"

  it "soft deletes the rate card" do
    expect(execution["data"]["destroyRateCard"]["id"]).to eq(rate_card.id)
    expect(rate_card.reload).to be_discarded
  end

  context "when the rate card belongs to another organization" do
    let(:rate_card) { create(:rate_card) }

    it "returns a not found error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end
end
