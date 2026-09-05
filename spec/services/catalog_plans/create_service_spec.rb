# frozen_string_literal: true

require "rails_helper"

RSpec.describe CatalogPlans::CreateService do
  subject(:result) { described_class.call(args) }

  let(:organization) { create(:organization) }
  let(:args) do
    {
      organization_id: organization.id,
      name: "Growth",
      code: "growth",
      description: "Growth plan",
      invoice_display_name: "Growth",
      currency: "USD"
    }
  end

  it "creates a catalog plan" do
    expect { result }.to change(CatalogPlan, :count).by(1)

    expect(result).to be_success
    expect(result.catalog_plan).to have_attributes(
      organization_id: organization.id,
      name: "Growth",
      code: "growth",
      description: "Growth plan",
      invoice_display_name: "Growth",
      currency: "USD"
    )
  end

  context "when the currency is invalid" do
    let(:args) { {organization_id: organization.id, name: "Growth", code: "growth", currency: "INVALID"} }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(result.error.messages[:currency]).to be_present
    end
  end
end
