# frozen_string_literal: true

require "rails_helper"

RSpec.describe "templates/payment_receipts/product_catalog.slim" do
  subject(:rendered_text) do
    html = Slim::Template.new(Rails.root.join("app/views/templates/payment_receipts/product_catalog.slim").to_s).render(payment_receipt)
    document = Nokogiri::HTML(html)
    document.css("style").remove
    document.xpath("//body//text()").map(&:text).join(" ").squish
  end

  let(:organization) { create(:organization) }
  let(:billing_entity) { organization.default_billing_entity }
  let(:customer) { create(:customer, organization:, name: "Pied Piper", legal_name: nil) }
  let(:invoice_type) { :contract }
  let(:invoice) do
    create(
      :invoice,
      organization:,
      billing_entity:,
      customer:,
      invoice_type:,
      number: "INV-001",
      fees_amount_cents: 2_800,
      sub_total_excluding_taxes_amount_cents: 2_800,
      sub_total_including_taxes_amount_cents: 2_800,
      total_amount_cents: 2_800,
      total_paid_amount_cents: 2_800
    )
  end
  let(:contract) { create(:contract, organization:, customer:, name: "Platform") }
  let(:product) { create(:product, organization:, name: "Compute", invoice_display_name: nil) }
  let(:product_filter) { nil }
  let(:rate_card_rate_attributes) { {} }
  let(:amount_details) { {} }
  let(:payment) do
    create(
      :payment,
      payable: invoice,
      organization:,
      customer:,
      amount_cents: 2_800,
      amount_currency: invoice.currency,
      status: "succeeded",
      payable_payment_status: "succeeded",
      created_at: Time.zone.parse("2026-11-02T10:00:00Z")
    )
  end
  let(:payment_receipt) { create(:payment_receipt, payment:, organization:, billing_entity:, number: "RCT-001") }

  def product_fee(fee_contract:, amount_cents:, **attributes)
    contract_rate_card = create(:contract_rate_card, organization:, contract: fee_contract, rate_card: create(:rate_card, organization:, product:))

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
      rate_card_rate: create(:rate_card_rate, organization:, rate_card: contract_rate_card.rate_card, **rate_card_rate_attributes),
      amount_cents:,
      taxes_amount_cents: 0,
      amount_currency: invoice.currency,
      units: 280,
      precise_unit_amount: 0.1,
      succeeded_at: Time.zone.parse("2026-10-15T10:00:00Z"),
      properties: {"from_datetime" => "2026-10-01T00:00:00Z", "to_datetime" => "2026-10-31T23:59:59Z"},
      **attributes
    )
  end

  before do
    billing_entity.update!(name: "Hooli", legal_name: nil, invoice_footer: "Hooli footer")
    product_fee(fee_contract: contract, amount_cents: 2_800, product_filter:, amount_details:)
  end

  it "identifies the receipt, the invoice it pays and the payment date" do
    expect(rendered_text).to include("Receipt Receipt number RCT-001 Invoice Number INV-001 Paid on #{I18n.l(Date.new(2026, 11, 2), format: :default)}")
  end

  it "bills from the billing entity to the customer, then states the amount paid" do
    expect(rendered_text).to match(/From Hooli.*Bill to Pied Piper/)
    expect(rendered_text).to include("€28.00 Paid on #{I18n.l(Date.new(2026, 11, 2), format: :default)} (Remaining to pay: €0.00)")
    expect(rendered_text).to include("Hooli footer")
  end

  it "details the contract's fees per billing period, like a v1 receipt details a subscription" do
    expect(rendered_text).to include("Platform details Fees from Oct 01, 2026 to Oct 31, 2026 Units Unit price Tax rate Amount Compute 280 €0.10 0.0% €28.00")
  end

  it "ends with the v1 totals" do
    expect(rendered_text).to include("Subtotal (excl. tax) €28.00 Tax (0%) €0.00 Subtotal (incl. tax) €28.00 Total €28.00")
    expect(rendered_text).not_to include("Amount due")
  end

  context "when the fee is billed on a product filter" do
    let(:product_filter) { create(:product_filter, organization:, product:, name: "EU", invoice_display_name: nil) }

    it "names the filter after the product" do
      expect(rendered_text).to include("Compute • EU 280 €0.10 0.0% €28.00")
    end
  end

  context "when the billed product has been discarded" do
    let(:product_filter) { create(:product_filter, organization:, product:, name: "EU", invoice_display_name: nil) }

    before do
      product_fee(fee_contract: contract, amount_cents: 200, true_up_parent_fee: invoice.fees.sole)
      product.discard!
      invoice.reload
      payment_receipt.reload
    end

    it "keeps the product, filter and true-up names in contract details" do
      expect(rendered_text).to include("Compute • EU 280 €0.10 0.0% €28.00")
      expect(rendered_text).to include(I18n.t("invoice.true_up_metric", metric: "Compute"))
    end

    context "when the invoice bills fees paid in advance" do
      let(:invoice_type) { :advance_charges }

      it "keeps the product and filter in advance fee lines" do
        expect(rendered_text).to include("Compute • EU")
        expect(rendered_text).to include("Already paid")
      end
    end
  end

  context "when the fee is graduated" do
    let(:rate_card_rate_attributes) do
      {
        rate_model: "graduated",
        rate_properties: {"graduated_ranges" => [
          {"from_value" => 0, "to_value" => 100, "per_unit_amount" => "0.1", "flat_amount" => "0"},
          {"from_value" => 100, "to_value" => nil, "per_unit_amount" => "0.1", "flat_amount" => "0"}
        ]}
      }
    end
    let(:amount_details) do
      {"graduated_ranges" => [
        {"from_value" => 0, "to_value" => 100, "units" => "100.0", "per_unit_amount" => "0.1", "per_unit_total_amount" => "10.0", "flat_unit_amount" => "0.0"},
        {"from_value" => 100, "to_value" => nil, "units" => "180.0", "per_unit_amount" => "0.1", "per_unit_total_amount" => "18.0", "flat_unit_amount" => "0.0"}
      ]}
    end

    it "details the tiers with a subtotal, as v1 does" do
      expect(rendered_text).to include(
        "Compute Fee per unit for the first 100 100 €0.10 0.0% €10.00 Fee per unit for 100 and above 180 €0.10 0.0% €18.00 Subtotal €28.00"
      )
    end
  end

  context "when the invoice bills fees paid in advance" do
    let(:invoice_type) { :advance_charges }

    it "lists the fees with their payment date and ends on already paid" do
      expect(rendered_text).to include("Item Units Unit price Tax rate Amount Compute #{I18n.l(Date.new(2026, 10, 15), format: :default)} 280 €0.10 0.0% €28.00")
      expect(rendered_text).to include("Subtotal (incl. tax) €28.00 Already paid €28.00")
    end
  end

  context "when the invoice bills several contracts" do
    let(:other_contract) { create(:contract, organization:, customer:, name: "Analytics") }

    before { product_fee(fee_contract: other_contract, amount_cents: 1_200) }

    it "sums each contract up front, then details it on its own page" do
      expect(rendered_text).to include("Item Amount Analytics €12.00 Platform €28.00")
      expect(rendered_text).to include("Analytics details Fees from Oct 01, 2026 to Oct 31, 2026")
      expect(rendered_text).to include("Platform details Fees from Oct 01, 2026 to Oct 31, 2026")
      expect(rendered_text).to include("Total €12.00")
    end
  end
end
