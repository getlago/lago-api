# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::CatalogPlanSerializer do
  subject(:serializer) { described_class.new(catalog_plan, root_name: "plan") }

  let(:catalog_plan) { create(:catalog_plan) }
  let(:result) { JSON.parse(serializer.to_json) }

  it "serializes the catalog plan" do
    expect(result["plan"]).to include(
      "lago_id" => catalog_plan.id,
      "name" => catalog_plan.name,
      "invoice_display_name" => catalog_plan.invoice_display_name,
      "code" => catalog_plan.code,
      "description" => catalog_plan.description,
      "currency" => catalog_plan.currency,
      "applied_rate_cards_count" => 0,
      "created_at" => catalog_plan.created_at.iso8601
    )
  end

  it "counts the plan's applied rate cards" do
    create(:plan_rate_card, organization: catalog_plan.organization, catalog_plan:)

    expect(result["plan"]["applied_rate_cards_count"]).to eq(1)
  end
end
