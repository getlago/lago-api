# frozen_string_literal: true

require "rails_helper"

RSpec.describe V1::CatalogPlanSerializer do
  subject(:serializer) { described_class.new(catalog_plan, root_name: "catalog_plan") }

  let(:catalog_plan) { create(:catalog_plan) }
  let(:result) { JSON.parse(serializer.to_json) }

  it "serializes the catalog plan" do
    expect(result["catalog_plan"]).to include(
      "lago_id" => catalog_plan.id,
      "name" => catalog_plan.name,
      "invoice_display_name" => catalog_plan.invoice_display_name,
      "code" => catalog_plan.code,
      "description" => catalog_plan.description,
      "currency" => catalog_plan.currency,
      "created_at" => catalog_plan.created_at.iso8601,
      "updated_at" => catalog_plan.updated_at.iso8601
    )
  end
end
