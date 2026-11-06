# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::ProductCatalogTreeService do
  subject(:result) { described_class.call(invoice:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, organization:, customer:) }

  let(:annual) { create(:contract, organization:, customer:, name: "Bistro annual") }
  let(:catering) { create(:contract, organization:, customer:, name: "Bistro catering") }

  let(:food) { create(:product_category, organization:, name: "Food", invoice_display_name: nil) }
  let(:salad) { create(:product, organization:, product_category: food, name: "Salad", invoice_display_name: nil) }
  let(:hamburger) { create(:product, organization:, product_category: food, name: "Hamburger", invoice_display_name: nil) }
  let(:wine) { create(:product, :fixed, :standalone, organization:, name: "Wine", invoice_display_name: nil) }
  let(:caesar) { create(:product_filter, organization:, product: salad, name: "Caesar", invoice_display_name: nil) }
  let(:caprese) { create(:product_filter, organization:, product: salad, name: "Caprese", invoice_display_name: nil) }

  let(:caesar_fee) { product_fee(annual, salad, amount_cents: 14_000, product_filter: caesar) }

  before do
    product_fee(catering, salad, amount_cents: 6_000)
    product_fee(annual, wine, amount_cents: 5_000)
    product_fee(annual, salad, amount_cents: 10_000, product_filter: caprese)
    product_fee(annual, salad, amount_cents: 200, true_up_parent_fee: caesar_fee)
    product_fee(annual, hamburger, amount_cents: 3_000)
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
      amount_cents:
    )
  end

  def tree
    result.contracts.map do |group|
      [
        group.contract.name,
        group.sections.map do |section|
          [
            section.category&.name,
            section.products.map do |product|
              [product.product.name, product.amount_cents, product.fees_count, product.filters.map { [it.filter.name, it.amount_cents, it.fees_count] }]
            end
          ]
        end
      ]
    end
  end

  it "sums the fees by contract, category, product and filter, in the order of the PDF" do
    expect(tree).to eq([
      [
        "Bistro annual",
        [
          [
            "Food",
            [
              ["Hamburger", 3_000, 1, []],
              # 14_000 caesar + 200 true-up + 10_000 caprese, the true-up counted under the filter of its parent
              ["Salad", 24_200, 3, [["Caesar", 14_200, 2], ["Caprese", 10_000, 1]]]
            ]
          ],
          [nil, [["Wine", 5_000, 1, []]]]
        ]
      ],
      ["Bistro catering", [["Food", [["Salad", 6_000, 1, []]]]]]
    ])
  end

  it "leaves out the fees of other invoices and other fee types" do
    product_fee(annual, wine, amount_cents: 1, fee_invoice: create(:invoice, organization:, customer:))
    create(:fee, invoice:, organization:, amount_cents: 2)

    expect(tree.first.last.last).to eq([nil, [["Wine", 5_000, 1, []]]])
  end

  context "with a discarded product" do
    before { wine.discard! }

    it "keeps its fees" do
      expect(tree.first.last.last).to eq([nil, [["Wine", 5_000, 1, []]]])
    end
  end
end
