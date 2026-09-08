# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::RateCards::Update do
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
  let(:rate_card) { create(:rate_card, organization:, name: "Before") }

  let(:input) { {id: rate_card.id, name: "After"} }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateRateCardInput!) {
        updateRateCard(input: $input) {
          id name code
          taxes { id code rate }
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "rate_cards:update"

  it "updates the rate card" do
    result_data = execution["data"]["updateRateCard"]

    expect(result_data["id"]).to eq(rate_card.id)
    expect(result_data["name"]).to eq("After")
  end

  context "with taxes" do
    let(:tax1) { create(:tax, organization:) }
    let(:tax2) { create(:tax, organization:) }
    let(:input) { {id: rate_card.id, taxCodes: [tax2.code]} }

    before { create(:rate_card_applied_tax, rate_card:, tax: tax1, organization:) }

    it "replaces and returns the taxes" do
      result_data = execution["data"]["updateRateCard"]

      expect(result_data["taxes"].pluck("code")).to eq([tax2.code])
    end

    context "when tax codes are empty" do
      let(:input) { {id: rate_card.id, taxCodes: []} }

      it "removes the tax override" do
        expect(execution["data"]["updateRateCard"]["taxes"]).to eq([])
      end
    end

    context "when tax codes are null" do
      let(:input) { {id: rate_card.id, taxCodes: nil} }

      it "keeps the existing tax" do
        taxes = execution["data"]["updateRateCard"]["taxes"]

        expect(taxes.pluck("code")).to eq([tax1.code])
      end
    end

    context "when a tax belongs to another organization" do
      let(:other_tax) { create(:tax) }
      let(:input) { {id: rate_card.id, taxCodes: [other_tax.code]} }

      it "returns a not found error and keeps the existing tax" do
        expect_graphql_error(result: execution, message: "Resource not found")
        expect(rate_card.reload.taxes).to eq([tax1])
      end
    end
  end

  context "when the rate card belongs to another organization" do
    let(:rate_card) { create(:rate_card) }

    it "returns a not found error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end
end
