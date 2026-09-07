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
  let(:product) { create(:product, organization:) }

  let(:input) do
    {
      productId: product.id,
      name: "Growth USD",
      code: "growth_usd",
      currency: "USD",
      billingTiming: "arrears"
    }
  end

  let(:mutation) do
    <<-GQL
      mutation($input: CreateRateCardInput!) {
        createRateCard(input: $input) {
          id name code currency billingTiming proration
          product { id }
          taxes { id code rate }
          ratesCount
          activeRate { id }
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "rate_cards:create"

  it "creates a rate card without rates" do
    result_data = execution["data"]["createRateCard"]

    expect(result_data["id"]).to be_present
    expect(result_data["name"]).to eq("Growth USD")
    expect(result_data["currency"]).to eq("USD")
    expect(result_data["proration"]).to eq(false) # omitted -> column default
    expect(result_data["product"]["id"]).to eq(product.id)
    expect(result_data["taxes"]).to eq([])
    expect(result_data["ratesCount"]).to eq(0)
    expect(result_data["activeRate"]).to be_nil
  end

  context "with taxes" do
    let(:tax1) { create(:tax, organization:) }
    let(:tax2) { create(:tax, organization:) }

    before { input[:taxCodes] = [tax1.code, tax2.code] }

    it "applies and returns the taxes" do
      result_data = execution["data"]["createRateCard"]

      expect(result_data["taxes"].pluck("code")).to match_array([tax1.code, tax2.code])
    end

    context "when a tax belongs to another organization" do
      let(:other_tax) { create(:tax) }

      before { input[:taxCodes] = [other_tax.code] }

      it "returns a not found error" do
        expect_graphql_error(result: execution, message: "Resource not found")
      end
    end
  end

  context "with nested rates" do
    let(:input) do
      {
        productId: product.id,
        name: "Growth USD",
        code: "growth_usd",
        currency: "USD",
        rates: [
          {
            code: "launch_price",
            effectiveFrom: 1.minute.ago.beginning_of_day.iso8601,
            rateModel: "standard",
            rateProperties: {amount: "10"},
            billingIntervalUnit: "month"
          }
        ]
      }
    end

    it "creates the rate card with its rates in one call" do
      result_data = execution["data"]["createRateCard"]

      expect(result_data["ratesCount"]).to eq(1)
      expect(result_data["activeRate"]["id"]).to be_present
    end
  end
end
