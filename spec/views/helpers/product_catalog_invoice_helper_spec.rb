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
  let(:billing_timing) { "arrears" }

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
    rate_card = create(:rate_card, organization:, product:, product_filter:, billing_timing:)
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
      expect(category.products.map(&:amount_cents)).to eq([300, 1_500])
      expect(standalone.name).to be_nil
      expect(standalone.products.map(&:name)).to eq(["Data transfer"])
      expect(standalone.amount_cents).to eq(700)
    end

    context "with a true-up on a filtered fee" do
      before { product_fee(compute, amount_cents: 200, true_up_parent_fee: invoice.fees.find_by(amount_cents: 500)) }

      it "lists the true-up under the filter of the fee it tops up" do
        compute_node = block.sections.first.products.last

        expect(compute_node.fees.map(&:amount_cents)).to eq([1_000])
        expect(compute_node.filters.sole.fees.map(&:amount_cents)).to eq([500, 200])
      end
    end
  end

  describe ".detail_rows" do
    subject(:rows) { described_class.detail_rows(section, "EUR") }

    let(:category_section) { described_class.contract_blocks(invoice).sole.sections.first }
    let(:standalone_section) { described_class.contract_blocks(invoice).sole.sections.last }

    context "with a category section" do
      let(:section) { category_section }

      it "nests products, periods and filters under the category" do
        expect(rows.map { [it.kind, it.indent, it.label] }).to eq([
          [:category, 0, "Infrastructure"],
          [:product, 1, "Analytics"],
          [:segment, 2, described_class.period_label(invoice.fees.find_by(amount_cents: 300))],
          [:product, 1, "Compute"],
          [:segment, 2, described_class.period_label(invoice.fees.find_by(amount_cents: 1_000))],
          [:filter, 2, "Compute EU"],
          [:segment, 3, described_class.period_label(invoice.fees.find_by(amount_cents: 500))]
        ])
        expect(rows.first.amount).to eq(MoneyHelper.format(Money.new(1_800, "EUR")))
        expect(rows.fourth.amount).to eq(MoneyHelper.format(Money.new(1_500, "EUR")))
      end
    end

    context "with standalone products" do
      let(:section) { standalone_section }

      it "starts products at the top level and adds tier lines below their period" do
        expect(rows.map { [it.kind, it.indent] }).to eq([
          [:product, 0],
          [:segment, 1],
          [:fee_detail, 2],
          [:fee_detail, 2],
          [:fee_detail, 2]
        ])
      end
    end
  end

  describe ".tiers by rate model" do
    subject(:lines) { described_class.tiers(fee).map { [it.label, it.units.to_s, it.unit_price, it.amount] } }

    let(:fee) do
      build_stubbed(
        :fee,
        amount_currency: "EUR",
        amount_cents:,
        units:,
        amount_details:,
        rate_card_rate: build_stubbed(:rate_card_rate, rate_model:)
      )
    end
    let(:amount_cents) { 0 }
    let(:units) { 0 }

    context "with a volume rate" do
      let(:rate_model) { "volume" }
      let(:units) { 3 }
      let(:amount_details) { {"per_unit_amount" => "400.0", "flat_unit_amount" => "100.0", "per_unit_total_amount" => "1200.0"} }

      it "lists the per-unit fee and the flat fee for all units" do
        expect(lines).to eq([
          ["Fee per unit", "3", "€400.00", "€1,200.00"],
          ["Flat fee for all units", "1", "€100.00", "€100.00"]
        ])
      end

      context "without a flat fee" do
        let(:amount_details) { {"per_unit_amount" => "400.0", "flat_unit_amount" => "0.0", "per_unit_total_amount" => "1200.0"} }

        it { is_expected.to be_empty }
      end
    end

    context "with a package rate" do
      let(:rate_model) { "package" }
      let(:amount_cents) { 18_000 }
      let(:amount_details) { {"free_units" => "500.0", "paid_units" => "11845.0", "per_package_size" => 1000, "per_package_unit_amount" => "15.0"} }

      it "lists the free units and the fee per package" do
        expect(lines).to eq([
          ["Free units for the first 500", "500", "€0.00", "€0.00"],
          ["Fee per package", "11845", "€15.00 per 1000", "€180.00"]
        ])
      end
    end

    context "with a percentage rate" do
      let(:rate_model) { "percentage" }
      let(:amount_details) do
        {
          "rate" => "2.9", "paid_units" => "1250.0", "free_units" => "100.0", "free_events" => 2, "paid_events" => 3,
          "fixed_fee_unit_amount" => "0.3", "fixed_fee_total_amount" => "0.9", "per_unit_total_amount" => "36.25",
          "min_max_adjustment_total_amount" => "1.5"
        }
      end

      it "lists free units, the rate, the fixed fee and the min/max adjustment" do
        expect(lines).to eq([
          ["Free units for 2 transactions", "100", "€0.00", "€0.00"],
          ["Rate on the amount", "1250", "2.9%", "€36.25"],
          ["Fixed fee per transaction", "3", "€0.30", "€0.90"],
          ["Adjustment for min/max per transaction", "1", "€1.50", "€1.50"]
        ])
      end
    end

    context "with a standard rate" do
      let(:rate_model) { "standard" }
      let(:amount_details) { {} }

      it { is_expected.to be_empty }
    end
  end

  describe ".fee_rows" do
    subject(:rows) { described_class.fee_rows([fee], 2).map { [it.kind, it.indent] } }

    let(:fee) do
      build_stubbed(
        :fee,
        amount_currency: "EUR",
        units: 3,
        amount_details: {"per_unit_amount" => "400.0", "flat_unit_amount" => "100.0", "per_unit_total_amount" => "1200.0"},
        rate_card_rate: build_stubbed(:rate_card_rate, rate_model: "volume"),
        pricing_unit_usage:,
        properties: {"from_datetime" => "2026-10-01T00:00:00Z", "to_datetime" => "2026-10-31T23:59:59Z"},
        invoice: build_stubbed(:invoice, customer: build_stubbed(:customer))
      )
    end
    let(:pricing_unit_usage) { nil }

    it "nests the details one level under the period" do
      expect(rows).to eq([[:segment, 2], [:fee_detail, 3], [:fee_detail, 3]])
    end

    context "with a pricing unit" do
      let(:pricing_unit_usage) { build_stubbed(:pricing_unit_usage, short_name: "CR", conversion_rate: 0.5) }

      it "shows the conversion first and nests the details one level deeper" do
        expect(rows).to eq([[:segment, 2], [:conversion, 3], [:fee_detail, 4], [:fee_detail, 4]])
      end
    end
  end

  describe "#advance_only?" do
    subject(:advance_only) { described_class.new(invoice).advance_only? }

    it { is_expected.to be(false) }

    context "when every fee comes from an advance rate card" do
      let(:billing_timing) { "advance" }

      it { is_expected.to be(true) }
    end
  end

  describe ".conversion_row" do
    subject(:row) { described_class.conversion_row(fee, 2) }

    let(:fee) { build_stubbed(:fee, amount_cents: 150_000, amount_currency: "EUR", pricing_unit_usage:) }
    let(:pricing_unit_usage) { build_stubbed(:pricing_unit_usage, short_name: "CR", conversion_rate: 0.5) }

    it "shows the conversion rate and the amount in the invoice currency" do
      expect(row.label).to eq("Conversion rate: 1 CR = €0.50")
      expect(row.amount).to eq("€1,500.00")
    end

    context "without a pricing unit" do
      let(:pricing_unit_usage) { nil }

      it { is_expected.to be_nil }
    end
  end

  describe ".range_label" do
    it "names the first, next and remaining tiers by their upper bound" do
      expect(described_class.range_label("fee", {"from_value" => 0, "to_value" => 10})).to eq("Fee for first 10 units")
      expect(described_class.range_label("fee", {"from_value" => 10, "to_value" => 50})).to eq("Fee for units up to 50")
      expect(described_class.range_label("fee", {"from_value" => 50, "to_value" => nil})).to eq("Fee for remaining units")
      expect(described_class.range_label("flat_fee", {"from_value" => 10, "to_value" => 50})).to eq("Flat fee for units up to 50")
    end
  end

  describe ".tiers" do
    subject(:tiers) { described_class.tiers(invoice.fees.find_by(amount_cents: 700)) }

    it "lists per-unit tiers, then flat fees" do
      expect(tiers.map(&:label)).to eq(
        [
          "Fee for first 100 units",
          "Fee for remaining units",
          "Flat fee for first 100 units"
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
