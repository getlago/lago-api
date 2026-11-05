# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvoiceProductFeesQuery do
  subject(:result) { described_class.call(organization:, search_term:, pagination:, filters:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, organization:, customer:) }
  let(:search_term) { nil }
  let(:pagination) { nil }
  let(:filters) { {invoice_id: invoice.id} }

  let(:annual) { create(:contract, organization:, customer:, name: "Bistro annual") }
  let(:catering) { create(:contract, organization:, customer:, name: "Bistro catering") }

  let(:food) { create(:product_category, organization:, name: "Food", invoice_display_name: nil) }
  let(:salad) { create(:product, organization:, product_category: food, name: "Salad", code: "salad", invoice_display_name: nil) }
  let(:hamburger) { create(:product, organization:, product_category: food, name: "Hamburger", code: "hamburger", invoice_display_name: nil) }
  let(:wine) { create(:product, :fixed, :standalone, organization:, name: "Wine", code: "wine", invoice_display_name: nil) }
  let(:caesar) { create(:product_filter, organization:, product: salad, name: "Caesar", code: "caesar", invoice_display_name: nil) }
  let(:caprese) { create(:product_filter, organization:, product: salad, name: "Caprese", code: "caprese", invoice_display_name: nil) }

  let(:catering_hamburger) { product_fee(catering, hamburger, amount_cents: 6_000) }

  before do
    product_fee(catering, salad, amount_cents: 6_001)
    product_fee(catering, hamburger, amount_cents: 3_000, true_up_parent_fee: catering_hamburger)
    product_fee(annual, wine, amount_cents: 5_000)
    product_fee(annual, salad, amount_cents: 10_000, product_filter: caprese)
    product_fee(annual, salad, amount_cents: 14_000, product_filter: caesar)
    product_fee(annual, hamburger, amount_cents: 3_001)
  end

  def product_fee(contract, product, amount_cents:, product_filter: nil, true_up_parent_fee: nil, fee_invoice: invoice)
    rate_card = create(:rate_card, organization:, product:, product_filter:)
    contract_rate_card = create(:contract_rate_card, organization:, contract:, rate_card:)

    create(
      :fee,
      invoice: fee_invoice,
      organization: fee_invoice.organization,
      subscription: nil,
      fee_type: "product",
      invoiceable_type: "Product",
      invoiceable_id: product.id,
      contract:,
      contract_rate_card:,
      rate_card_rate: create(:rate_card_rate, organization:, rate_card:),
      product_filter: true_up_parent_fee ? nil : product_filter,
      true_up_parent_fee:,
      amount_cents:,
      properties: {"from_datetime" => "2026-10-01T00:00:00Z", "to_datetime" => "2026-10-31T23:59:59Z"}
    )
  end

  def amounts
    result.fees.map(&:amount_cents)
  end

  it "orders the fees by contract, category, product, filter and period" do
    expect(amounts).to eq([
      3_001, # annual > food > hamburger
      14_000, # annual > food > salad > caesar
      10_000, # annual > food > salad > caprese
      5_000, # annual > standalone > wine
      6_000, # catering > food > hamburger
      3_000, # catering > food > hamburger, true-up right after its parent
      6_001 # catering > food > salad
    ])
  end

  context "with a contract without a name or a plan" do
    before { product_fee(create(:contract, organization:, customer:, name: nil, catalog_plan: nil), wine, amount_cents: 1) }

    it "lists it first, as the PDF does" do
      expect(amounts.first).to eq(1)
    end
  end

  it "leaves out the fees of other invoices and other fee types" do
    other_invoice = create(:invoice, organization:, customer:)
    product_fee(annual, wine, amount_cents: 1, fee_invoice: other_invoice)
    create(:fee, invoice:, organization:, amount_cents: 2)

    expect(amounts).not_to include(1, 2)
  end

  context "when the invoice belongs to another organization" do
    let(:filters) { {invoice_id: create(:invoice).id} }

    it "fails with a not found error" do
      expect(result).to be_failure
      expect(result.error.error_code).to eq("invoice_not_found")
    end
  end

  context "with a contract filter" do
    let(:filters) { {invoice_id: invoice.id, contract_id: catering.id} }

    it "returns the fees of that contract" do
      expect(amounts).to eq([6_000, 3_000, 6_001])
    end
  end

  context "with a product category filter" do
    let(:filters) { {invoice_id: invoice.id, product_category_id: food.id} }

    it "leaves out the standalone products" do
      expect(amounts).to eq([3_001, 14_000, 10_000, 6_000, 3_000, 6_001])
    end
  end

  context "with the standalone products filter" do
    let(:filters) { {invoice_id: invoice.id, standalone_products: true} }

    it "returns the fees of products without a category" do
      expect(amounts).to eq([5_000])
    end
  end

  context "with a products filter" do
    let(:filters) { {invoice_id: invoice.id, product_ids: [salad.id]} }

    it "returns the fees of those products" do
      expect(amounts).to eq([14_000, 10_000, 6_001])
    end
  end

  context "with a product filters filter" do
    let(:filters) { {invoice_id: invoice.id, product_filter_ids: [caesar.id]} }

    it "returns the fees of those filters" do
      expect(amounts).to eq([14_000])
    end

    context "with a true-up on a filtered fee" do
      before { product_fee(annual, salad, amount_cents: 200, true_up_parent_fee: invoice.fees.find_by(amount_cents: 14_000)) }

      it "keeps the true-up with the filter of the fee it tops up" do
        expect(amounts).to eq([14_000, 200])
      end
    end

    context "with the fees without a filter" do
      let(:filters) { {invoice_id: invoice.id, product_filter_ids: [caesar.id], without_product_filter: true} }

      it "returns the union of both" do
        expect(amounts).to eq([3_001, 14_000, 5_000, 6_000, 3_000, 6_001])
      end
    end
  end

  context "with a product type filter" do
    let(:filters) { {invoice_id: invoice.id, product_type: "fixed"} }

    it "returns the fees of products of that type" do
      expect(amounts).to eq([5_000])
    end

    context "when the product type is unknown" do
      let(:filters) { {invoice_id: invoice.id, product_type: "bogus"} }

      it "fails with the product types allowed" do
        expect(result).to be_failure
        expect(result.error.messages).to eq(product_type: ["value_is_invalid"])
        expect(result.error.meta).to eq(product_type: {allowed_values: %w[metered fixed]})
      end
    end
  end

  context "with a malformed id" do
    let(:filters) { {invoice_id: invoice.id, product_ids: ["not-a-uuid"]} }

    it "matches nothing" do
      expect(amounts).to eq([])
    end
  end

  context "with a search term" do
    let(:search_term) { "caes" }

    it "matches the product and filter names and codes" do
      expect(amounts).to eq([14_000])
    end
  end

  context "with a discarded product" do
    before { wine.discard! }

    it "still returns its fees" do
      expect(amounts).to include(5_000)
    end
  end

  context "with pagination" do
    let(:pagination) { {page: 2, limit: 2} }

    it "returns the requested page" do
      expect(amounts).to eq([10_000, 5_000])
      expect(result.fees.total_count).to eq(7)
    end

    context "when the limit is above the maximum" do
      let(:pagination) { {page: 1, limit: 500} }

      it "caps it" do
        expect(result.fees.limit_value).to eq(described_class::MAX_LIMIT)
      end
    end
  end
end
