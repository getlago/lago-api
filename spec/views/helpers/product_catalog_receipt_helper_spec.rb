# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductCatalogReceiptHelper do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, organization:, customer:, invoice_type: :contract) }
  let(:platform) { create(:contract, organization:, customer:, name: "Platform") }
  let(:analytics) { create(:contract, organization:, customer:, name: "Analytics") }

  let(:seats) { create(:product, organization:, name: "Seats", product_type: :fixed, billable_metric: nil) }
  let(:storage) { create(:product, organization:, name: "Storage") }
  let(:compute) { create(:product, organization:, name: "Compute") }

  def product_fee(product, contract: platform, amount_cents: 1_000, taxes_amount_cents: 0, true_up_parent_fee: nil)
    contract_rate_card = create(:contract_rate_card, organization:, contract:, rate_card: create(:rate_card, organization:, product:))

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
      amount_cents:,
      taxes_amount_cents:,
      true_up_parent_fee:,
      properties: {"from_datetime" => "2026-10-01T00:00:00Z", "to_datetime" => "2026-10-31T23:59:59Z"}
    )
  end

  describe ".contracts" do
    subject(:contracts) { described_class.contracts(invoice) }

    before do
      product_fee(compute, contract: platform)
      product_fee(storage, contract: analytics)
    end

    it "groups the product fees by contract, sorted by contract name" do
      expect(contracts.map { |contract, fees| [contract.name, fees.map(&:invoiceable)] }).to eq([["Analytics", [storage]], ["Platform", [compute]]])
    end
  end

  describe ".periods" do
    subject(:periods) { described_class.periods(invoice.fees.reload.to_a) }

    let(:compute_fee) { product_fee(compute) }
    let(:storage_fee) { product_fee(storage) }
    let(:seats_fee) { product_fee(seats) }
    let(:true_up_fee) { product_fee(compute, true_up_parent_fee: compute_fee) }

    before do
      storage_fee
      true_up_fee
      seats_fee
    end

    it "lists fixed products first, then the metered ones by name, each true-up after the fee it tops up" do
      expect(periods.sole.fees).to eq([seats_fee, compute_fee, true_up_fee, storage_fee])
      expect(periods.sole.from_datetime).to eq(Time.zone.parse("2026-10-01T00:00:00Z"))
    end
  end

  describe ".contract_total" do
    it "adds the taxes of the contract's fees to their amount" do
      fees = [product_fee(compute, amount_cents: 1_000, taxes_amount_cents: 200), product_fee(storage, amount_cents: 500, taxes_amount_cents: 100)]

      expect(described_class.contract_total(fees)).to eq(Money.new(1_800, "EUR"))
    end
  end
end
