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
      "add_ons_count" => 0,
      "customers_count" => 0,
      "plans_count" => 0,
      "charges_count" => 0,
      "created_at" => tax.created_at.iso8601
    )
  end

  describe "applied_to_organization" do
    context "when the tax is applied to the default billing entity" do
      let(:tax) { create(:tax, :applied_to_billing_entity) }

      it "returns true" do
        result = JSON.parse(serializer.to_json)

        expect(result["tax"]["applied_to_organization"]).to be(true)
      end
    end

    context "when the tax is applied to a non-default billing entity" do
      let(:organization) { create(:organization) }
      let(:billing_entity) { create(:billing_entity, organization:) }
      let(:tax) { create(:tax, :applied_to_billing_entity, organization:, billing_entity:) }

      it "returns false" do
        result = JSON.parse(serializer.to_json)

        expect(result["tax"]["applied_to_organization"]).to be(false)
      end
    end

    context "when only the deprecated applied_to_organization column is set" do
      let(:tax) { create(:tax, applied_to_organization: true) }

      it "ignores the column and returns false" do
        result = JSON.parse(serializer.to_json)

        expect(result["tax"]["applied_to_organization"]).to be(false)
      end
    end

    context "when the default billing entity id is provided as an option" do
      subject(:serializer) do
        described_class.new(tax, root_name: "tax", default_billing_entity_id: billing_entity.id)
      end

      let(:organization) { create(:organization) }
      let(:billing_entity) { organization.default_billing_entity }
      let(:tax) { create(:tax, :applied_to_billing_entity, organization:) }

      it "returns true" do
        result = JSON.parse(serializer.to_json)

        expect(result["tax"]["applied_to_organization"]).to be(true)
      end
    end
  end
end
