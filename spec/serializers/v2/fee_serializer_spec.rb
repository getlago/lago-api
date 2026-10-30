# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::FeeSerializer do
  subject(:serializer) { described_class.new(fee, root_name: "fee") }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:) }
  let_it_be(:contract) { create(:contract, organization:, customer:) }
  let_it_be(:invoice) { create(:invoice, organization:, customer:) }
  let_it_be(:tax) { create(:tax, organization:) }
  let_it_be(:pricing_unit) { create(:pricing_unit, organization:) }
  let_it_be(:billable_metric) { create(:billable_metric, organization:) }
  let_it_be(:billable_metric_filter) do
    create(:billable_metric_filter, organization:, billable_metric:, key: "region", values: %w[eu us])
  end
  let_it_be(:product_category) { create(:product_category, organization:, name: "Infrastructure", invoice_display_name: nil) }
  let_it_be(:product, refind: true) do
    create(:product, organization:, billable_metric:, product_category:, invoice_display_name: "Compute hours")
  end
  let_it_be(:product_filter) { create(:product_filter, organization:, product:, name: "Europe", invoice_display_name: nil) }
  let_it_be(:rate_card, refind: true) { create(:rate_card, :advance, organization:, product:, product_filter:) }
  let_it_be(:rate) { create(:rate_card_rate, organization:, rate_card:) }
  let_it_be(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }

  before_all do
    create(:product_filter_value, organization:, product_filter:, billable_metric_filter:, value: "eu")
  end

  let(:properties) do
    {
      "from_datetime" => "2025-01-01T00:00:00.000000Z",
      "to_datetime" => "2025-01-31T23:59:59.999999Z",
      "product_filter_values" => {"region" => ["eu"]}
    }
  end
  let(:fee_attributes) do
    {
      invoice:,
      subscription: nil,
      fee_type: :product,
      invoiceable: product,
      contract:,
      contract_rate_card:,
      rate_card_rate: rate,
      product_filter:,
      pay_in_advance: true,
      units: 12,
      total_aggregated_units: 12,
      events_count: 3,
      unit_amount_cents: 10,
      precise_unit_amount: BigDecimal("10.5"),
      amount_cents: 126,
      precise_amount_cents: BigDecimal("126"),
      precise_coupons_amount_cents: BigDecimal("6"),
      taxes_amount_cents: 24,
      taxes_precise_amount_cents: BigDecimal("24"),
      grouped_by: {"country" => "fr"},
      properties:
    }
  end
  let(:fee) { create(:fee, fee_attributes) }
  let(:applied_tax) { create(:fee_applied_tax, fee:, tax:) }
  let(:result) { JSON.parse(serializer.to_json)["fee"] }

  before { applied_tax }

  it "serializes the fee" do
    expect(result).to eq(
      "lago_id" => fee.id,
      "lago_invoice_id" => invoice.id,
      "fee_type" => "product",
      "lago_customer_id" => customer.id,
      "external_customer_id" => customer.external_id,
      "lago_contract_id" => contract.id,
      "external_contract_id" => contract.external_id,
      "lago_product_id" => product.id,
      "product_code" => product.code,
      "lago_product_category_id" => product_category.id,
      "product_category_code" => product_category.code,
      "lago_product_filter_id" => product_filter.id,
      "product_filter_code" => product_filter.code,
      "lago_rate_card_id" => rate_card.id,
      "rate_card_code" => rate_card.code,
      "lago_rate_id" => rate.id,
      "rate_code" => rate.code,
      "lago_rate_override_id" => nil,
      "lago_true_up_parent_fee_id" => nil,
      "lago_true_up_fee_id" => nil,
      "event_transaction_id" => nil,
      "display_on_invoice" => true,
      "product_invoice_display_name" => "Compute hours",
      "product_category_invoice_display_name" => "Infrastructure",
      "product_filter_invoice_display_name" => "Europe",
      "filters" => {"region" => ["eu"]},
      "billing_timing" => "advance",
      "grouped_by" => {"country" => "fr"},
      "from_datetime" => "2025-01-01T00:00:00Z",
      "to_datetime" => "2025-01-31T23:59:59Z",
      "currency" => "EUR",
      "units" => "12.0",
      "total_aggregated_units" => "12.0",
      "events_count" => 3,
      "unit_amount_cents" => 10,
      "precise_unit_amount_cents" => "1050.0",
      "amount_cents" => 126,
      "sub_total_excluding_taxes_amount_cents" => 120,
      "taxes_amount_cents" => 24,
      "total_amount_cents" => 150,
      "amount_details" => {},
      "pricing_unit_details" => nil,
      "payment_status" => "pending",
      "succeeded_at" => nil,
      "failed_at" => nil,
      "refunded_at" => nil,
      "created_at" => fee.created_at.iso8601,
      "updated_at" => fee.updated_at.iso8601,
      "deleted_at" => nil
    )
  end

  context "when the fee predates stored filter values" do
    let(:properties) { super().except("product_filter_values") }

    it "falls back to the current filter values" do
      expect(result["filters"]).to eq("region" => ["eu"])
    end
  end

  context "with a fixed product billed in arrears" do
    let(:fixed_product) { create(:product, :fixed, :standalone, organization:) }
    let(:fixed_rate_card) { create(:rate_card, organization:, product: fixed_product) }
    let(:fixed_contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card: fixed_rate_card) }
    let(:fixed_rate) { create(:rate_card_rate, organization:, rate_card: fixed_rate_card) }
    let(:properties) { super().except("product_filter_values") }
    let(:fee) do
      create(
        :fee,
        fee_attributes.merge(
          invoiceable: fixed_product,
          contract_rate_card: fixed_contract_rate_card,
          rate_card_rate: fixed_rate,
          product_filter: nil,
          pay_in_advance: false
        )
      )
    end

    it "leaves the category and filter fields empty" do
      expect(result).to include(
        "lago_product_id" => fixed_product.id,
        "lago_product_category_id" => nil,
        "product_category_code" => nil,
        "product_category_invoice_display_name" => nil,
        "lago_product_filter_id" => nil,
        "product_filter_code" => nil,
        "product_filter_invoice_display_name" => nil,
        "filters" => nil,
        "lago_rate_card_id" => fixed_rate_card.id,
        "lago_rate_id" => fixed_rate.id,
        "rate_code" => fixed_rate.code,
        "billing_timing" => "arrears"
      )
    end
  end

  context "when the fee is billed on an event and has no invoice yet" do
    let(:fee) do
      create(
        :fee,
        fee_attributes.merge(
          invoice: nil,
          organization:,
          billing_entity: customer.billing_entity,
          pay_in_advance_event_transaction_id: "tx_123"
        )
      )
    end

    it "takes the customer from the contract" do
      expect(result).to include(
        "lago_invoice_id" => nil,
        "lago_customer_id" => customer.id,
        "external_customer_id" => customer.external_id,
        "event_transaction_id" => "tx_123"
      )
    end
  end

  context "with graduated amount details" do
    let(:fee) do
      create(
        :fee,
        fee_attributes.merge(
          amount_details: {
            "graduated_ranges" => [
              {"from_value" => 0, "to_value" => 10, "per_unit_amount" => "1.0", "units" => "10.0", "total_with_flat_amount" => "10.0"},
              {"from_value" => 11, "to_value" => nil, "per_unit_amount" => "0.5", "units" => "2.0", "total_with_flat_amount" => "1.0"}
            ]
          }
        )
      )
    end

    it "shows each tier by its upper bound only" do
      ranges = result["amount_details"]["graduated_ranges"]

      expect(ranges.map { it["to_value"] }).to eq(["10", nil])
      expect(ranges.map(&:keys)).to all(eq(%w[to_value per_unit_amount units total_with_flat_amount]))
    end
  end

  context "with a pricing unit usage" do
    let(:pricing_unit_usage) { create(:pricing_unit_usage, fee:, pricing_unit:) }

    before { pricing_unit_usage }

    it "serializes the pricing unit details" do
      expect(result["pricing_unit_details"]).to eq(
        "lago_pricing_unit_id" => pricing_unit.id,
        "pricing_unit_code" => pricing_unit.code,
        "short_name" => pricing_unit.short_name,
        "amount_cents" => 200,
        "precise_amount_cents" => "200.0000000001",
        "unit_amount_cents" => 10,
        "precise_unit_amount" => "0.1",
        "conversion_rate" => "1.0"
      )
    end
  end

  context "with a true-up fee" do
    let(:true_up_fee) { create(:fee, fee_attributes.merge(product_filter: nil, true_up_parent_fee: fee)) }

    before { true_up_fee }

    it "links the fees both ways" do
      expect(result["lago_true_up_fee_id"]).to eq(true_up_fee.id)
      expect(described_class.new(true_up_fee).serialize[:lago_true_up_parent_fee_id]).to eq(fee.id)
    end
  end

  context "when the fee is deleted" do
    before { fee.discard! }

    it "renders the deletion time" do
      expect(result["deleted_at"]).to eq(fee.deleted_at.iso8601)
    end
  end

  context "when the product and the rate card are discarded" do
    before do
      fee
      product.discard!
      rate_card.discard!
      fee.reload
    end

    it "still names them" do
      expect(result).to include(
        "lago_product_id" => product.id,
        "product_code" => product.code,
        "lago_product_category_id" => product_category.id,
        "lago_rate_card_id" => rate_card.id,
        "rate_card_code" => rate_card.code,
        "display_on_invoice" => true
      )
    end
  end

  context "with every expansion" do
    subject(:serializer) { described_class.new(fee, root_name: "fee", includes: described_class.expandable_names) }

    let(:as_json) { ->(serializer) { JSON.parse(serializer.serialize.to_json) } }

    it "renders each related record flat after the fee" do
      expect(result.keys.last(8)).to eq(%w[applied_taxes invoice product product_filter rate_card rate contract customer])
      expect(result).to include(
        "applied_taxes" => [
          {
            "lago_id" => applied_tax.id,
            "lago_fee_id" => fee.id,
            "lago_tax_id" => tax.id,
            "tax_name" => "VAT",
            "tax_code" => tax.code,
            "tax_rate" => 20.0,
            "tax_description" => "French Standard VAT",
            "amount_cents" => 200,
            "created_at" => applied_tax.created_at.iso8601,
            "updated_at" => applied_tax.updated_at.iso8601
          }
        ],
        "invoice" => as_json.call(V2::InvoiceSerializer.new(invoice)),
        "product" => as_json.call(V2::ProductSerializer.new(product)),
        "product_filter" => as_json.call(V2::ProductFilterSerializer.new(product_filter)),
        "rate_card" => as_json.call(V2::RateCardSerializer.new(rate_card)),
        "rate" => as_json.call(V2::RateCardRateSerializer.new(rate)),
        "contract" => as_json.call(V2::ContractSerializer.new(contract)),
        "customer" => as_json.call(V2::CustomerSerializer.new(customer))
      )
      expect(result["product"]).not_to have_key("product_category")
    end

    context "with several applied taxes" do
      let(:earlier_applied_tax) { create(:fee_applied_tax, fee:, tax: create(:tax, organization:), created_at: 1.day.ago) }

      before { earlier_applied_tax }

      it "lists them in creation order" do
        expect(result["applied_taxes"].map { it["lago_id"] }).to eq([earlier_applied_tax.id, applied_tax.id])
      end
    end

    context "when the product and the rate card are discarded" do
      before do
        fee
        product.discard!
        rate_card.discard!
        fee.reload
      end

      it "still expands them" do
        expect(result["product"]).to include("lago_id" => product.id, "code" => product.code)
        expect(result["rate_card"]).to include("lago_id" => rate_card.id, "code" => rate_card.code)
      end
    end

    context "when the fee is billed on an event and has no invoice yet" do
      let(:fee) { create(:fee, fee_attributes.merge(invoice: nil, organization:, billing_entity: customer.billing_entity)) }

      it "renders the invoice as null" do
        expect(result).to include("invoice" => nil)
      end
    end

    context "when the fee has no filter" do
      let(:fee) { create(:fee, fee_attributes.merge(product_filter: nil)) }

      it "renders it as null" do
        expect(result["product_filter"]).to be_nil
      end
    end
  end

  context "when a discarded product of another organization shares the fee's product id" do
    let(:foreign_product) { create(:product, organization: create(:organization)) }
    let(:fee) { create(:fee, fee_attributes.except(:invoiceable).merge(invoiceable_type: "Product", invoiceable_id: foreign_product.id)) }

    before { foreign_product.discard! }

    it "does not load it" do
      expect(result).to include("lago_product_id" => nil, "product_code" => nil)
    end
  end

  context "when the fee references a product of another organization" do
    let(:foreign_product) { create(:product, organization: create(:organization)) }
    let(:fee) { create(:fee, fee_attributes.merge(invoiceable: foreign_product)) }

    it "does not expose it" do
      expect(result).to include(
        "lago_product_id" => nil,
        "product_code" => nil,
        "product_invoice_display_name" => nil,
        "lago_product_category_id" => nil
      )
    end
  end
end
