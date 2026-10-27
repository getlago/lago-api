# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::ContractSerializer do
  subject(:payload) { described_class.new(contract, options).serialize }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:catalog_plan) { create(:catalog_plan, organization:, code: "enterprise") }
  let(:contract) do
    create(
      :contract,
      :terminated,
      organization:,
      customer:,
      catalog_plan:,
      external_id: "contract-42",
      name: "Annual deal",
      billing_time: :anniversary,
      consolidate_invoice: false,
      purchase_order_number: "PO-42",
      started_at: Time.zone.parse("2026-01-10T08:00:00Z"),
      ended_at: Time.zone.parse("2026-12-31T00:00:00Z"),
      terminated_at: Time.zone.parse("2026-09-30T12:00:00Z"),
      created_at: Time.zone.parse("2026-01-05T09:00:00Z"),
      updated_at: Time.zone.parse("2026-09-30T12:00:01Z")
    )
  end
  let(:options) { {} }
  # A contract is never deleted, so it renders no deleted_at.
  let(:flat_payload) do
    {
      lago_id: contract.id,
      external_id: "contract-42",
      lago_customer_id: customer.id,
      external_customer_id: customer.external_id,
      name: "Annual deal",
      plan_code: "enterprise",
      status: "terminated",
      billing_time: "anniversary",
      consolidate_invoice: false,
      purchase_order_number: "PO-42",
      billing_anchor_date: nil,
      effective_billing_anchor_date: "2026-01-10",
      started_at: "2026-01-10T08:00:00Z",
      ended_at: "2026-12-31T00:00:00Z",
      terminated_at: "2026-09-30T12:00:00Z",
      canceled_at: nil,
      skip_invoice_custom_sections: false,
      created_at: "2026-01-05T09:00:00Z",
      updated_at: "2026-09-30T12:00:01Z"
    }
  end

  let(:created_at) { Time.zone.parse("2026-09-28T10:00:00.000001Z") }
  # Created oldest first, the reverse of the listed order, the last two at the same microsecond.
  let(:applied_rate_cards) do
    [2, 1, 0, 0].map { create(:contract_rate_card, organization:, contract:, created_at: created_at - it.seconds) }
  end
  let(:sections) { create_list(:invoice_custom_section, 4, organization:) }
  # Selected oldest first, in another order than the sections were created. The last two are
  # selected at the same microsecond, in creation order but with ascending ids, so that only the
  # id tiebreak lists them in reverse.
  let(:selections) do
    tied_ids = Array.new(2) { SecureRandom.uuid }.sort
    sections.values_at(2, 0, 1, 3).zip([2, 1, 0, 0], [nil, nil, *tied_ids]).map do |invoice_custom_section, age, id|
      create(:contract_applied_invoice_custom_section, **{id:}.compact, contract:, invoice_custom_section:, created_at: created_at - age.seconds)
    end
  end
  let(:deleted_section) { create(:invoice_custom_section, organization:) }
  let(:other_contract) { create(:contract, organization:, customer:) }

  before do
    applied_rate_cards
    create(:contract_rate_card, organization:, contract:).discard!
    create(:contract_rate_card, organization:, contract: other_contract)

    selections
    create(:contract_applied_invoice_custom_section, contract:, invoice_custom_section: deleted_section)
    # Discarded directly: InvoiceCustomSections::DestroyService would delete the selection as well.
    deleted_section.discard!
    create(:contract_applied_invoice_custom_section, contract: other_contract)
  end

  it "serializes the flat contract, without expansions" do
    expect(payload).to eq(flat_payload)
  end

  context "with the applied_rate_cards expansion" do
    let(:options) { {includes: %i[applied_rate_cards]} }

    it "embeds the kept cards, the latest created first, ties ordered by id" do
      expected = [*applied_rate_cards.last(2).sort_by(&:id).reverse, applied_rate_cards.second, applied_rate_cards.first]

      expect(payload).to eq(
        flat_payload.merge(applied_rate_cards: expected.map { V2::ContractAppliedRateCardSerializer.new(it).serialize })
      )
    end
  end

  context "with the plan expansion" do
    let(:options) { {includes: %i[plan]} }

    it "embeds the flat plan" do
      expect(payload).to eq(flat_payload.merge(plan: V2::CatalogPlanSerializer.new(catalog_plan).serialize))
      expect(payload[:plan]).not_to have_key(:taxes)
    end

    # Read from the database, so that the plan comes from the association rather than the factory.
    context "when the plan is discarded" do
      before do
        catalog_plan.discard!
        contract.reload
      end

      it "embeds it with its deleted_at" do
        expect(payload).to eq(flat_payload.merge(plan: V2::CatalogPlanSerializer.new(catalog_plan).serialize))
        expect(payload[:plan][:deleted_at]).to eq(catalog_plan.deleted_at.iso8601)
      end
    end

    context "without a plan" do
      let(:catalog_plan) { nil }

      it "renders it as null" do
        expect(payload).to eq(flat_payload.merge(plan_code: nil, plan: nil))
      end
    end
  end

  context "with the customer expansion" do
    let(:options) { {includes: %i[customer]} }

    it "embeds the flat customer" do
      expect(payload).to eq(flat_payload.merge(customer: V2::CustomerSerializer.new(customer).serialize))
    end

    # Read from the database, so that the customer comes from the association rather than the factory.
    context "when the customer is discarded" do
      before do
        customer.discard!
        contract.reload
      end

      it "embeds it with its deleted_at" do
        expect(payload).to eq(flat_payload.merge(customer: V2::CustomerSerializer.new(customer).serialize))
        expect(payload[:customer][:deleted_at]).to eq(customer.deleted_at.iso8601)
      end
    end
  end

  context "with the invoice_custom_sections expansion" do
    let(:options) { {includes: %i[invoice_custom_sections]} }

    it "embeds the kept selected sections, the last selected first, ties ordered by selection id" do
      expected = selections.reverse.map(&:invoice_custom_section)

      expect(payload).to eq(
        flat_payload.merge(invoice_custom_sections: expected.map { V2::InvoiceCustomSectionSerializer.new(it).serialize })
      )
    end
  end

  context "with every expansion" do
    let(:options) { {includes: %i[invoice_custom_sections customer plan applied_rate_cards]} }

    it "embeds them after the contract, in their declared order" do
      expect(payload.keys).to eq([*flat_payload.keys, :applied_rate_cards, :plan, :customer, :invoice_custom_sections])
    end
  end
end
