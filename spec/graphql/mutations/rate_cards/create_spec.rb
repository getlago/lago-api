# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::RateCards::Create do
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
  let(:product_item) { create(:product_item, organization:) }

  let(:input) do
    {
      productItemId: product_item.id,
      name: "Growth USD",
      code: "growth_usd",
      currency: "USD",
      billingTiming: "arrears",
      rates: [
        {
          effectiveDatetime: 1.minute.ago.iso8601,
          rateModel: "standard",
          rateProperties: {amount: "10"},
          billingIntervalUnit: "month"
        }
      ]
    }
  end

  let(:mutation) do
    <<-GQL
      mutation($input: CreateRateCardInput!) {
        createRateCard(input: $input) {
          id name code currency billingTiming proration
          productItem { id }
          rates { id status rateModel rateProperties }
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "rate_cards:create"

  it "creates a rate card with its rates" do
    result_data = execution["data"]["createRateCard"]

    expect(result_data["id"]).to be_present
    expect(result_data["name"]).to eq("Growth USD")
    expect(result_data["currency"]).to eq("USD")
    expect(result_data["proration"]).to eq("full")
    expect(result_data["productItem"]["id"]).to eq(product_item.id)
    expect(result_data["rates"].count).to eq(1)
    expect(result_data["rates"].first["status"]).to eq("active")
  end
end
