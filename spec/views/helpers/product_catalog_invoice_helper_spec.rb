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

  def product_fee(product, amount_cents:, product_filter: nil, amount_details: {}, true_up_parent_fee: nil, hidden: false)
    rate_card = if hidden
      create(:rate_card, :advance, organization:, product:, product_filter:, display_on_invoice: false)
    else
      create(:rate_card, organization:, product:, product_filter:)
    end
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
      rate_card_rate: create(:rate_card_rate, organization:, rate_card: contract_rate_card.rate_card),
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

    context "with a paid-in-advance fee regrouped on this invoice" do
      before { product_fee(transfer, amount_cents: 250, hidden: true) }

      it "includes it in the summary and the details" do
        expect(described_class.summary_lines(invoice).map { [it.name, it.amount_cents] }).to eq([["Infrastructure", 1_800], ["Data transfer", 950]])
        expect(block.sections.last.products.sole.fees.map(&:amount_cents)).to contain_exactly(700, 250)
      end
    end

    context "with a true-up on a filtered fee" do
      before { product_fee(compute, amount_cents: 200, true_up_parent_fee: invoice.fees.find_by(amount_cents: 500)) }

      it "lists the true-up under the filter of the fee it tops up" do
        compute_node = block.sections.first.products.last

        expect(compute_node.fees.map(&:amount_cents)).to eq([1_000])
        expect(compute_node.filters.sole.fees.map(&:amount_cents)).to eq([500, 200])
      end
    end

    context "with true-ups on several fees of one product" do
      before do
        second_fee = product_fee(analytics, amount_cents: 400)
        product_fee(analytics, amount_cents: 60, true_up_parent_fee: second_fee)
        product_fee(analytics, amount_cents: 30, true_up_parent_fee: invoice.fees.find_by(amount_cents: 300))
      end

      it "lists each true-up right after the fee it tops up" do
        fees = block.sections.first.products.first.fees

        expect(fees.size).to eq(4)
        fees.each_with_index.select { |fee, _| fee.true_up_parent_fee_id }.each do |true_up, index|
          expect(fees[index - 1].id).to eq(true_up.true_up_parent_fee_id)
        end
      end
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

  describe "queries" do
    def contract_blocks_query_count
      capture_sql { described_class.contract_blocks(Invoice.find(invoice.id)) }.size
    end

    def unnamed_contract_fee(amount_cents)
      unnamed_contract = create(:contract, organization:, customer:, name: nil, catalog_plan: create(:catalog_plan, organization:))
      rate_card = create(:rate_card, organization:, product: analytics)
      contract_rate_card = create(:contract_rate_card, organization:, contract: unnamed_contract, rate_card:)

      create(
        :fee,
        invoice:,
        subscription: nil,
        fee_type: "product",
        invoiceable: analytics,
        invoice_display_name: nil,
        contract: unnamed_contract,
        contract_rate_card:,
        rate_card_rate: create(:rate_card_rate, organization:, rate_card: contract_rate_card.rate_card),
        amount_cents:,
        properties: {"from_datetime" => "2026-10-01T00:00:00Z", "to_datetime" => "2026-10-31T23:59:59Z"}
      )
    end

    it "does not grow with true-ups and contracts" do
      product_fee(compute, amount_cents: 50, true_up_parent_fee: invoice.fees.find_by(amount_cents: 1_000))
      unnamed_contract_fee(200)
      baseline = contract_blocks_query_count

      product_fee(analytics, amount_cents: 30, true_up_parent_fee: invoice.fees.find_by(amount_cents: 300))
      unnamed_contract_fee(250)

      expect(contract_blocks_query_count).to eq(baseline)
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

    context "when the fee has no billing period" do
      before { invoice.fees.find_by(amount_cents: 300).update!(properties: {"from_datetime" => nil}) }

      it "returns an empty label" do
        expect(label).to eq("")
      end
    end
  end
end
