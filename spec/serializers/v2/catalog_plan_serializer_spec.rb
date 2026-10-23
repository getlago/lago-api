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

  context "when taxes are expanded" do
    let(:options) { {includes: %i[taxes]} }
    let(:organization) { catalog_plan.organization }
    let(:created_at) { Time.zone.parse("2026-09-28T10:00:00.000001Z") }
    let(:taxes) { [3, 2, 1].map { create(:tax, organization:, created_at: created_at - it.days) } }
    # Linked oldest first, in another order than the taxes were created. The last two are linked
    # at the same microsecond, with ascending ids, so that only the id tiebreak lists them in reverse.
    let(:links) do
      tied_ids = Array.new(2) { SecureRandom.uuid }.sort
      taxes.values_at(1, 0, 2).zip([1, 0, 0], [nil, *tied_ids]).map do |tax, age, id|
        create(:plan_applied_tax, :catalog_plan, **{id:}.compact, catalog_plan:, organization:, tax:, created_at: created_at - age.seconds)
      end
    end

    before do
      links
      # A discarded tax whose link was kept, and the tax of another plan.
      create(:plan_applied_tax, :catalog_plan, catalog_plan:, organization:).tax.discard!
      create(:plan_applied_tax, :catalog_plan, organization:)
    end

    it "embeds its kept taxes in the v2 shape, latest linked first" do
      expect(payload).to eq(
        flat_payload.merge(
          taxes: links.reverse.map(&:tax).map do |tax|
            {
              lago_id: tax.id,
              name: tax.name,
              code: tax.code,
              rate: tax.rate,
              description: tax.description,
              created_at: tax.created_at.iso8601,
              updated_at: tax.updated_at.iso8601,
              deleted_at: nil
            }
          end
        )
      )
    end
  end
end
