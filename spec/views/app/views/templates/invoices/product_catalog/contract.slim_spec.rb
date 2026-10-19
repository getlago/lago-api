# frozen_string_literal: true

require "rails_helper"

RSpec.describe "templates/invoices/product_catalog/contract.slim" do
  subject(:rendered_text) do
    html = Slim::Template.new(Rails.root.join("app/views/templates/invoices/product_catalog/contract.slim").to_s).render(invoice)
    document = Nokogiri::HTML(html)
    document.css("style").remove
    document.xpath("//body//text()").map(&:text).join(" ").squish
  end

  let(:organization) { create(:organization) }
  let(:billing_entity) { organization.default_billing_entity }
  let(:customer) { create(:customer, organization:, name: "Pied Piper", legal_name: nil) }
  let(:invoice) do
    create(:invoice, organization:, billing_entity:, customer:, invoice_type: :contract, number: "INV-001", self_billed:)
  end
  let(:self_billed) { false }
  let(:contract) { create(:contract, organization:, customer:, name: "Platform") }
  let(:category) { create(:product_category, organization:, name: "Infrastructure", invoice_display_name: nil) }
  let(:product) { create(:product, organization:, product_category: category, name: "Compute", invoice_display_name: nil) }
  let(:rate_card) { create(:rate_card, organization:, product:) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }

  before do
    billing_entity.update!(name: "Hooli")
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
      amount_cents: 2_800,
      amount_currency: invoice.currency,
      units: 280,
      precise_unit_amount: 0.1,
      properties: {"from_datetime" => "2026-10-01T00:00:00Z", "to_datetime" => "2026-10-31T23:59:59Z"}
    )
  end

  it "renders the summary with one line per category" do
    expect(rendered_text).to include("Description Amount Infrastructure")
  end

  it "renders the details page per contract, down to the billing period" do
    expect(rendered_text).to include("Details Platform - Invoice INV-001")
    expect(rendered_text).to include("Compute From 1 Oct to 31 Oct 2026 280")
  end

  it "bills from the billing entity to the customer" do
    expect(rendered_text).to match(/From Hooli.*Bill to Pied Piper/)
  end

  context "when the invoice is self billed" do
    let(:self_billed) { true }

    it "swaps the issuer and the recipient" do
      expect(rendered_text).to match(/From Pied Piper.*Bill to Hooli/)
    end
  end
end
