# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditNoteProductCatalogHelper do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, organization:, customer:, number: "INV-001", purchase_order_number: nil) }
  let(:credit_note) { create(:credit_note, organization:, customer:, invoice:) }
  let(:contract) { create(:contract, organization:, customer:, name: "Platform", purchase_order_number: "PO-42") }
  let(:category) { create(:product_category, organization:, name: "Infrastructure", invoice_display_name: nil) }
  let(:product) { create(:product, organization:, product_category: category, name: "Compute") }
  let(:filter) { create(:product_filter, organization:, product:, invoice_display_name: "Compute EU") }

  def product_fee(product:, amount_cents:, product_filter: nil, true_up_parent_fee: nil, fee_contract: contract)
    rate_card = create(:rate_card, organization:, product:, product_filter:)
    contract_rate_card = create(:contract_rate_card, organization:, contract: fee_contract, rate_card:)

    create(
      :fee,
      invoice:,
      subscription: nil,
      fee_type: "product",
      invoiceable_type: "Product",
      invoiceable_id: product.id,
      invoice_display_name: nil,
      contract: fee_contract,
      contract_rate_card:,
      rate_card_rate: create(:rate_card_rate, organization:, rate_card: contract_rate_card.rate_card),
      product_filter:,
      amount_cents:,
      true_up_parent_fee:,
      properties: {"from_datetime" => "2026-10-01T00:00:00Z", "to_datetime" => "2026-10-31T23:59:59Z"}
    )
  end

  def credit(fee, amount_cents)
    create(:credit_note_item, credit_note:, fee:, amount_cents:, precise_amount_cents: amount_cents)
  end

  describe "#summary_lines" do
    subject(:lines) { described_class.new(credit_note).summary_lines }

    let(:fee) { product_fee(product:, amount_cents: 1_000) }

    before do
      credit(fee, 250)
      product_fee(product:, amount_cents: 800)
    end

    it "sums credited amounts only, excluding uncredited fees and full invoice amounts" do
      expect(lines.map { [it.name, it.amount_cents] }).to eq([["Infrastructure", 250]])
    end
  end

  describe "#contract_blocks" do
    subject(:block) { described_class.new(credit_note).contract_blocks.sole }

    let(:parent_fee) { product_fee(product:, amount_cents: 1_000, product_filter: filter) }
    let(:true_up_fee) { product_fee(product:, amount_cents: 200, true_up_parent_fee: parent_fee) }
    let(:credits) { [[parent_fee, 300], [true_up_fee, 50]] }

    before do
      credits.each { |fee, amount_cents| credit(fee, amount_cents) }
      product_fee(product:, amount_cents: 900)
    end

    it "groups credited totals by category, product and the parent's filter" do
      section = block.sections.sole
      product_node = section.products.sole

      expect(block.title).to eq("Platform - #{I18n.t("credit_note.document_name")} #{credit_note.number} - PO-42")
      expect([section.name, section.amount_cents, product_node.amount_cents]).to eq(["Infrastructure", 350, 350])
      expect(product_node.filters.sole.name).to eq("Compute EU")
      expect(product_node.filters.sole.items.map { it.item.amount_cents }).to eq([300, 50])
    end

    it "renders only credited segment amounts without unit prices or quantities" do
      rows = described_class.detail_rows(block.sections.sole, "EUR")

      expect(rows.map { [it.kind, it.indent] }).to eq([
        [:category, 0], [:product, 1], [:filter, 2], [:segment, 3], [:segment, 3]
      ])
      expect(rows.last(2).map(&:amount)).to eq(["€3.00", "€0.50"])
      expect(rows.last(2).all? { !it.respond_to?(:units) && !it.respond_to?(:unit_price) }).to be(true)
    end

    it "uses the credited fee name when its period is unavailable" do
      parent_fee.update!(properties: {})

      segment = described_class.detail_rows(block.sections.sole, "EUR").find { it.kind == :segment }

      expect(segment.label).to eq(parent_fee.invoice_name)
    end

    context "when only the true-up is credited" do
      let(:credits) { [[true_up_fee, 50]] }

      it "resolves the category and filter from the uncredited parent" do
        section = block.sections.sole
        product_node = section.products.sole

        expect([section.name, product_node.filters.sole.name]).to eq(["Infrastructure", "Compute EU"])
        expect(product_node.filters.sole.items.map { it.item.amount_cents }).to eq([50])
      end
    end

    context "with an uncategorized product" do
      let(:uncategorized_product) { create(:product, organization:, product_category: nil, name: "Data transfer") }
      let(:uncategorized_fee) { product_fee(product: uncategorized_product, amount_cents: 125) }

      before { credit(uncategorized_fee, 75) }

      it "places it in the final uncategorized section with credited totals" do
        section = block.sections.last

        expect([section.name, section.amount_cents, section.products.sole.amount_cents]).to eq([nil, 75, 75])
      end
    end

    context "with multiple contracts" do
      let(:second_contract) { create(:contract, organization:, customer:, name: "Annual") }
      let(:second_fee) { product_fee(product:, amount_cents: 200, fee_contract: second_contract) }

      before { credit(second_fee, 125) }

      it "orders blocks by contract name and keeps each credited fee in its contract" do
        blocks = described_class.contract_blocks(credit_note)

        expect(blocks.map(&:title)).to eq([
          "Annual - #{I18n.t("credit_note.document_name")} #{credit_note.number}",
          "Platform - #{I18n.t("credit_note.document_name")} #{credit_note.number} - PO-42"
        ])
        expect(blocks.map { it.sections.sum(&:amount_cents) }).to eq([125, 350])
      end
    end

    context "with discarded category and filter records" do
      before do
        category.discard
        filter.discard
      end

      it "continues to group using the tenant-scoped discarded records" do
        expect([block.sections.sole.name, block.sections.sole.products.sole.filters.sole.name]).to eq(["Infrastructure", "Compute EU"])
      end
    end
  end
end
