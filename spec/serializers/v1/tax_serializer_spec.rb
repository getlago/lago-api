# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::TaxSerializer do
  subject(:serializer) { described_class.new(tax, root_name: "tax") }

  let(:tax) { create(:tax) }

  it "serializes the object" do
    result = JSON.parse(serializer.to_json)

    expect(result["tax"]).to include(
      "lago_id" => tax.id,
      "name" => tax.name,
      "code" => tax.code,
      "rate" => tax.rate,
      "description" => tax.description,
      "applied_to_organization" => false,
      "applied_to_billing_entities_codes" => [],
      "add_ons_count" => 0,
      "customers_count" => 0,
      "plans_count" => 0,
      "charges_count" => 0,
      "created_at" => tax.created_at.iso8601
    )
  end

  context "when the tax is applied to the default billing entity" do
    let(:tax) { create(:tax, :applied_to_billing_entity) }

    it "sets applied_to_organization to true and lists the billing entity code" do
      result = JSON.parse(serializer.to_json)

      expect(result["tax"]["applied_to_organization"]).to eq(true)
      expect(result["tax"]["applied_to_billing_entities_codes"]).to eq([tax.organization.default_billing_entity.code])
    end
  end

  context "when the tax is applied only to a non-default billing entity" do
    let(:billing_entity) { create(:billing_entity, organization: tax.organization) }

    before { create(:billing_entity_applied_tax, tax:, billing_entity:, organization: tax.organization) }

    it "keeps applied_to_organization false but lists the billing entity code" do
      result = JSON.parse(serializer.to_json)

      expect(result["tax"]["applied_to_organization"]).to eq(false)
      expect(result["tax"]["applied_to_billing_entities_codes"]).to eq([billing_entity.code])
    end
  end
end
