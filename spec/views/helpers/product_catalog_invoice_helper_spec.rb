# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductCatalogInvoiceHelper do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, organization:, customer:, number: "INV-001", purchase_order_number: nil) }
  let(:contract) { create(:contract, organization:, customer:, name: "Platform", purchase_order_number: "PO-42") }

  let(:infrastructure) { create(:product_category, organization:, name: "Infrastructure", invoice_display_name: nil) }
  let(:compute) { create(:product, organization:, product_category: infrastructure, name: "Compute") }
  let(:analytics) { create(:product, organization:, product_category: infrastructure, name: "Analytics") }
  let(:transfer) { create(:product, organization:, product_category: nil, name: "Data transfer") }
  let(:eu) { create(:product_filter, organization:, product: compute, invoice_display_name: "Compute EU") }

  let(:graduated_percentage_details) do
    {
      "graduated_percentage_ranges" => [
        {"from_value" => 0, "to_value" => 100, "rate" => "2.0", "units" => "100.0", "flat_unit_amount" => "1.0", "per_unit_total_amount" => "2.0"},
        {"from_value" => 100, "to_value" => nil, "rate" => "1.0", "units" => "50.0", "flat_unit_amount" => "0.0", "per_unit_total_amount" => "0.5"}
      ]
    }
  end

  before do
    product_fee(compute, amount_cents: 1_000)
    product_fee(compute, amount_cents: 500, product_filter: eu)
    product_fee(analytics, amount_cents: 300)
    product_fee(transfer, amount_cents: 700, amount_details: graduated_percentage_details)
  end

  def product_fee(product, amount_cents:, product_filter: nil, amount_details: {}, true_up_parent_fee: nil)
    rate_card = create(:rate_card, organization:, product:, product_filter:)
    contract_rate_card = create(:contract_rate_card, organization:, contract:, rate_card:)

    create(
      :fee,
      invoice:,
      subscription: nil,
      fee_type: "product",
      invoiceable_type: "Product",
      invoiceable_id: product.id,
      invoice_display_name: nil,
      contract:,
      contract_rate_card:,
      product_filter:,
      amount_cents:,
      amount_details:,
      true_up_parent_fee:,
      properties: {"from_datetime" => "2026-10-01T00:00:00Z", "to_datetime" => "2026-10-31T23:59:59Z"}
    )
  end

  describe ".summary_lines" do
    subject(:lines) { described_class.summary_lines(invoice) }

    it "lists categories first, then standalone products" do
      expect(lines.map { [it.name, it.amount_cents] }).to eq([["Infrastructure", 1_800], ["Data transfer", 700]])
    end
  end

  describe ".contract_blocks" do
    subject(:block) { described_class.contract_blocks(invoice).sole }

    it "titles the block with the contract, the invoice and the purchase order" do
      expect(block.title).to eq("Platform - Invoice INV-001 - PO-42")
    end

    it "groups by category, product and filter, sorted by name" do
      category, standalone = block.sections

      expect(category.name).to eq("Infrastructure")
      expect(category.products.map(&:name)).to eq(%w[Analytics Compute])
      expect(category.products.last.filters.map(&:name)).to eq(["Compute EU"])
      expect(standalone.name).to be_nil
      expect(standalone.products.map(&:name)).to eq(["Data transfer"])
      expect(standalone.amount_cents).to eq(700)
    end
  end

  describe ".tiers" do
    subject(:tiers) { described_class.tiers(invoice.fees.find_by(amount_cents: 700)) }

    it "lists per-unit tiers, then flat fees" do
      expect(tiers.map(&:label)).to eq(
        [
          "Fee per unit for the first 100",
          "Fee per unit for 100 and above",
          "Flat fee for first 100"
        ]
      )
      expect(tiers.map(&:unit_price)).to eq(["2%", "1%", "€1.00"])
    end

    context "without graduated ranges" do
      subject(:tiers) { described_class.tiers(invoice.fees.find_by(amount_cents: 300)) }

      it { is_expected.to eq([]) }
    end
  end

  describe ".period_label" do
    subject(:label) { described_class.period_label(invoice.fees.find_by(amount_cents: 300)) }

    it "uses the fee boundaries in the customer timezone" do
      expect(label).to eq("From 1 Oct to 31 Oct 2026")
    end

    context "with a true-up fee" do
      subject(:label) { described_class.period_label(true_up_fee) }

      let(:true_up_fee) { product_fee(analytics, amount_cents: 50, true_up_parent_fee: invoice.fees.find_by(amount_cents: 300)) }

      it "names the true-up after its parent" do
        expect(label).to eq("Analytics - True-up")
      end
    end
  end
end
