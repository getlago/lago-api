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
  let(:category) { create(:product_category, organization:, name: "Infrastructure", invoice_display_name: nil) }
  let(:product) { create(:product, organization:, product_category: category, name: "Compute", invoice_display_name: nil) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card: create(:rate_card, organization:, product:)) }
  let(:product_filter) { nil }
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

  before do
    billing_entity.update!(name: "Hooli", invoice_footer: "Hooli footer")
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
      rate_card_rate: create(:rate_card_rate, organization:, rate_card: contract_rate_card.rate_card),
      amount_cents: 2_800,
      amount_currency: invoice.currency,
      units: 280,
      precise_unit_amount: 0.1,
      properties: {"from_datetime" => "2026-10-01T00:00:00Z", "to_datetime" => "2026-10-31T23:59:59Z"}
    )
  end

  it "identifies the receipt, the invoice it pays and the payment date" do
    expect(rendered_text).to include("Receipt Receipt number RCT-001 Invoice Number INV-001 Paid on #{I18n.l(Date.new(2026, 11, 2), format: :default)}")
  end

  it "bills from the billing entity to the customer, then states the amount paid" do
    expect(rendered_text).to match(/From Hooli.*Bill to Pied Piper/)
    expect(rendered_text).to include("€28.00 Paid on #{I18n.l(Date.new(2026, 11, 2), format: :default)} (Remaining to pay: €0.00)")
  end

  it "summarizes the invoice like the catalog invoice, with one line per category" do
    expect(rendered_text).to include("Description Amount Infrastructure €28.00")
    expect(rendered_text).to include("Subtotal (excl. tax) €28.00 Total €28.00 Amount due €0.00")
    expect(rendered_text).to include("Hooli footer")
  end

  it "details each contract down to the billing period" do
    expect(rendered_text).to include("Details Platform - Invoice INV-001")
    expect(rendered_text).to include("Compute €28.00 From 1 Oct to 31 Oct 2026 280")
  end

  context "when the fee is billed on a product filter" do
    let(:product_filter) { create(:product_filter, organization:, product:, name: "EU", invoice_display_name: nil) }

    it "details the fee under its filter" do
      expect(rendered_text).to include("Compute €28.00 EU From 1 Oct to 31 Oct 2026 280")
    end
  end

  context "when the invoice bills fees paid in advance" do
    let(:invoice_type) { :advance_charges }

    it "shows the total as already paid, with nothing due" do
      expect(rendered_text).to include("Description Amount Infrastructure €28.00")
      expect(rendered_text).to include("Subtotal (excl. tax) €28.00 Already paid €28.00")
      expect(rendered_text).not_to include("Amount due")
    end
  end
end
