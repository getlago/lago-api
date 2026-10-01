# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::ContractSerializer do
  subject(:payload) { described_class.new(contract, root_name: "contract", includes:).serialize }

  let(:includes) { %i[applied_rate_cards] }

  let(:contract) { create(:contract) }
  let(:created_at) { Time.zone.parse("2026-09-28T10:00:00.000001Z") }
  # Oldest first, the reverse of the listed order.
  let!(:applied_rate_cards) { [2, 1, 0, 0].map { create(:contract_rate_card, organization: contract.organization, contract:, created_at: created_at - it.seconds) } }

  it "embeds the applied rate cards newest first, ties ordered by id" do
    expected = applied_rate_cards.sort_by { [it.created_at, it.id] }.reverse.map(&:id)

    expect(payload[:applied_rate_cards].pluck(:lago_id)).to eq(expected)
  end

  # What a v2 render passes without expand: contracts are never deleted, so no deleted_at.
  context "with deleted_at only" do
    let(:includes) { %i[deleted_at] }
    let(:customer) { create(:customer) }
    let(:catalog_plan) { create(:catalog_plan, organization: customer.organization) }
    let(:contract) do
      create(
        :contract, :terminated,
        customer:, catalog_plan:, name: "Annual deal", billing_time: :anniversary, consolidate_invoice: false,
        purchase_order_number: "PO-42", skip_invoice_custom_sections: true,
        started_at: Time.zone.parse("2026-01-10T08:00:00Z"), ended_at: Time.zone.parse("2026-12-31T00:00:00Z"),
        terminated_at: Time.zone.parse("2026-09-30T12:00:00Z"),
        created_at: Time.zone.parse("2026-01-05T09:00:00Z"), updated_at: Time.zone.parse("2026-09-30T12:00:01Z")
      )
    end

    it "renders the flat contract" do
      expect(payload).to eq(
        lago_id: contract.id,
        external_id: contract.external_id,
        lago_customer_id: customer.id,
        external_customer_id: customer.external_id,
        name: "Annual deal",
        plan_code: catalog_plan.code,
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
        skip_invoice_custom_sections: true,
        created_at: "2026-01-05T09:00:00Z",
        updated_at: "2026-09-30T12:00:01Z"
      )
    end
  end

  context "with invoice custom sections" do
    let(:includes) { %i[invoice_custom_sections] }
    # Selected oldest first, the reverse of the listed order, and the sections created the other way
    # around: listed by the sections instead of their selection, the oldest selection would come first.
    let!(:applied_sections) do
      [1, 0, 0].map do |age|
        invoice_custom_section = create(:invoice_custom_section, organization: contract.organization, created_at: created_at + age.seconds)
        create(:contract_applied_invoice_custom_section, contract:, invoice_custom_section:, created_at: created_at - age.seconds)
      end
    end

    it "expands them in the order they were selected, newest first, ties ordered by id" do
      expected = applied_sections.sort_by { [it.created_at, it.id] }.reverse.map(&:invoice_custom_section_id)

      expect(payload[:invoice_custom_sections].pluck(:lago_id)).to eq(expected)
    end
  end
end
