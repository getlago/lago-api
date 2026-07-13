# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::TaxWithBillingEntitiesSerializer do
  subject(:serializer) { described_class.new(tax, root_name: "tax", default_billing_entity:) }

  let(:tax) { create(:tax) }
  let(:default_billing_entity) { tax.organization.default_billing_entity }

  it "serializes the base attributes and the billing entity fields" do
    result = JSON.parse(serializer.to_json)

    expect(result["tax"]).to include(
      "lago_id" => tax.id,
      "name" => tax.name,
      "code" => tax.code,
      "rate" => tax.rate,
      "description" => tax.description,
      "applied_to_organization" => false,
      "applied_to_billing_entities_codes" => [],
      "created_at" => tax.created_at.iso8601
    )
  end

  context "when the tax is applied to the default billing entity" do
    let(:tax) { create(:tax, :applied_to_billing_entity) }

    it "sets applied_to_organization to true and lists the billing entity code" do
      result = JSON.parse(serializer.to_json)["tax"]

      expect(result["applied_to_organization"]).to eq(true)
      expect(result["applied_to_billing_entities_codes"]).to eq([default_billing_entity.code])
    end
  end

  context "when the tax is applied only to a non-default billing entity" do
    let(:billing_entity) { create(:billing_entity, organization: tax.organization) }

    before { create(:billing_entity_applied_tax, tax:, billing_entity:, organization: tax.organization) }

    it "keeps applied_to_organization false but lists the billing entity code" do
      result = JSON.parse(serializer.to_json)["tax"]

      expect(result["applied_to_organization"]).to eq(false)
      expect(result["applied_to_billing_entities_codes"]).to eq([billing_entity.code])
    end
  end

  context "when no default billing entity is passed" do
    let(:default_billing_entity) { nil }
    let(:tax) { create(:tax, :applied_to_billing_entity) }

    it "returns applied_to_organization false" do
      result = JSON.parse(serializer.to_json)["tax"]

      expect(result["applied_to_organization"]).to eq(false)
    end
  end
end
