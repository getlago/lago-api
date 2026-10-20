# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::CatalogPlanSerializer do
  subject(:payload) { described_class.new(catalog_plan, options).serialize }

  let(:catalog_plan) do
    create(
      :catalog_plan,
      name: "Premium",
      invoice_display_name: "Premium plan",
      code: "premium",
      description: "Premium monthly plan",
      currency: "USD",
      created_at: Time.zone.parse("2026-09-01T08:30:00Z"),
      deleted_at:
    )
  end
  let(:deleted_at) { nil }
  let(:options) { {} }
  let(:flat_payload) do
    {
      lago_id: catalog_plan.id,
      name: "Premium",
      invoice_display_name: "Premium plan",
      code: "premium",
      description: "Premium monthly plan",
      currency: "USD",
      created_at: "2026-09-01T08:30:00Z",
      deleted_at: nil
    }
  end

  it "serializes the catalog plan, with a null deletion timestamp" do
    expect(payload).to eq(flat_payload)
  end

  context "when the catalog plan has applied rate cards" do
    before do
      create(:plan_rate_card, organization: catalog_plan.organization, catalog_plan:)
      create(:plan_rate_card, organization: catalog_plan.organization, catalog_plan:, deleted_at: Time.current)
    end

    it "renders no count of them" do
      expect(payload).to eq(flat_payload)
    end

    # Only the plan webhooks ask for it.
    context "when counts are included" do
      let(:options) { {includes: %i[counts]} }

      it "counts the kept ones only" do
        expect(payload).to eq(flat_payload.merge(applied_rate_cards_count: 1))
      end
    end
  end

  context "when the catalog plan is deleted" do
    let(:deleted_at) { Time.zone.parse("2026-10-01T12:00:00Z") }

    it "includes the deletion timestamp" do
      expect(payload).to eq(flat_payload.merge(deleted_at: "2026-10-01T12:00:00Z"))
    end
  end

  context "when taxes are included" do
    let(:options) { {includes: %i[taxes]} }
    let(:tax) do
      create(
        :tax,
        organization: catalog_plan.organization,
        name: "VAT",
        code: "fr_vat",
        rate: 20.0,
        description: "French Standard VAT",
        created_at: Time.zone.parse("2026-08-15T10:00:00Z")
      )
    end

    before do
      create(:plan_applied_tax, :catalog_plan, catalog_plan:, tax:, organization: catalog_plan.organization)
      create(:tax, organization: catalog_plan.organization)
    end

    it "embeds the plan's taxes only, as v1 taxes" do
      expect(payload).to eq(
        flat_payload.merge(
          taxes: [
            {
              lago_id: tax.id,
              name: "VAT",
              code: "fr_vat",
              rate: 20.0,
              description: "French Standard VAT",
              applied_to_organization: false,
              add_ons_count: 0,
              customers_count: 0,
              plans_count: 0,
              charges_count: 0,
              commitments_count: 0,
              created_at: "2026-08-15T10:00:00Z"
            }
          ]
        )
      )
    end
  end
end
