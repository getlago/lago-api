# frozen_string_literal: true

require "rails_helper"

RSpec.describe "templates/credit_notes/product_catalog/credit_note.slim" do
  subject(:rendered_document) do
    html = Slim::Template.new(template).render(credit_note)
    Nokogiri::HTML(html)
  end

  let(:template) { Rails.root.join("app/views/templates/credit_notes/product_catalog/credit_note.slim") }
  let(:organization) { create(:organization) }
  let(:billing_entity) { organization.default_billing_entity }
  let(:customer) do
    create(:customer, organization:, name: "Recipient Inc", legal_name: nil, address_line1: "2 Recipient Road")
  end
  let(:invoice) do
    create(:invoice, organization:, billing_entity:, customer:, number: "INV-001", currency: "USD",
      total_amount_cents: 99_999, purchase_order_number: "PO-123")
  end
  let(:contract) { create(:contract, organization:, customer:, name: "Platform") }
  let(:category) { create(:product_category, organization:, name: "Infrastructure", invoice_display_name: nil) }
  let(:product) { create(:product, organization:, product_category: category, name: "Data Export") }
  let(:fee) { create_product_fee(product:, amount_cents: 10_000, invoice_display_name: "Export Package") }
  let(:credit_note) do
    create(:credit_note, organization:, customer:, invoice:, number: "CN-001", issuing_date: Date.new(2026, 10, 5),
      total_amount_currency: "USD", total_amount_cents: 550, taxes_amount_cents: 50,
      credit_amount_currency: "USD", credit_amount_cents: 550)
  end

  def create_product_fee(product:, amount_cents:, invoice_display_name: nil)
    rate_card = create(:rate_card, organization:, product:)
    contract_rate_card = create(:contract_rate_card, organization:, contract:, rate_card:)

    create(:fee, invoice:, subscription: nil, fee_type: "product", invoiceable_type: "Product",
      invoiceable_id: product.id, invoice_display_name:, contract:, contract_rate_card:,
      rate_card_rate: create(:rate_card_rate, organization:, rate_card:), amount_cents:, amount_currency: "USD",
      properties: {"from_datetime" => "2026-10-01T00:00:00Z", "to_datetime" => "2026-10-31T23:59:59Z"})
  end

  def credit(fee, amount_cents)
    create(:credit_note_item, credit_note:, fee:, amount_cents:, precise_amount_cents: amount_cents,
      amount_currency: "USD")
  end

  before { I18n.locale = :en }

  context "with a credited product fee and an uncredited product fee" do
    let(:uncredited_fee) { create_product_fee(product:, amount_cents: 20_000, invoice_display_name: "Uncredited Package") }

    before do
      credit(fee, 500)
      uncredited_fee
    end

    it "renders the grouped product summary and credited details without full fee or invoice amounts" do
      document = rendered_document
      summary = document.css("table.document-table--summary tbody tr").map { |row| row.css("td").map { |cell| cell.text.squish } }
      details_text = document.css(".details-page").text.squish

      expect(document.css("table.document-table--summary thead th").map { it.text.squish }).to eq(%w[Description Amount])
      expect(document.css("table.document-table--summary tbody tr").last.css("td").all? { it["class"].split.include?("cell--at-end") }).to be(true)
      expect(document.at_css("h2.amount-due + p")["class"].split).to include("body-1-emphasis")
      expect(summary).to include(["Infrastructure", "$5.00"])
      expect(summary).not_to include(["Export Package", "$5.00"])
      expect(details_text).to include(I18n.t("invoice.details_title"), "Platform - Credit note CN-001 - PO-123", "Data Export", "$5.00")
      expect(details_text).to include("From 1 Oct to 31 Oct 2026")
      expect(details_text).not_to include("$100.00", "$200.00", "$999.99", "Uncredited Package")
      expect(document.text.squish).to include(I18n.t("credit_note.total"), "$5.50")
    end
  end

  context "when taxes are applied" do
    before do
      credit(fee, 500)
      create(:credit_note_applied_tax, credit_note:, organization:, tax_name: "VAT", tax_rate: 10,
        amount_cents: 50, amount_currency: "USD", base_amount_cents: 500)
    end

    it "renders the exact tax base, rate, tax amount, and total" do
      document = rendered_document
      tax_row = document.xpath("//tr").find { |row| row.text.include?("VAT") }
      totals = document.css("table.document-totals tr").map { |row| row.css("td").map { |cell| cell.text.squish } }

      expect(tax_row.css("td").map { |cell| cell.text.squish }).to eq(["VAT (10.0% on $5.00)", "$0.50"])
      expect(totals).to include([I18n.t("credit_note.total"), "$5.50"])
    end
  end

  context "when rendering a self-billed credit note" do
    let(:invoice) do
      create(:invoice, :self_billed, organization:, billing_entity:, customer:, number: "INV-001", currency: "USD",
        total_amount_cents: 99_999)
    end

    before { credit(fee, 500) }

    it "reverses the address blocks and renders the self-billing footer" do
      text = rendered_document.xpath("//body//text()").map(&:text).join(" ").squish

      expect(text).to match(/From #{Regexp.escape(customer.display_name)}.*2 Recipient Road.*Credit to #{Regexp.escape(billing_entity.name)}/)
      expect(text).to include(I18n.t("credit_note.self_billed.footer"))
      expect(text).not_to include("$999.99")
    end
  end

  context "when purchase order number and customer metadata are present" do
    before do
      credit(fee, 500)
      create(:customer_metadata, customer:, organization:, key: "Department", value: "Research")
    end

    it "renders the invoice purchase order number and displayable metadata" do
      text = rendered_document.xpath("//body//text()").map(&:text).join(" ").squish

      expect(text).to include(I18n.t("credit_note.purchase_order_number"), "PO-123", "Department", "Research")
    end
  end

  context "when a product fee and a non-product fee are credited together" do
    let(:add_on) { create(:add_on, organization:, name: "Support") }
    let(:add_on_fee) do
      create(:one_off_fee, invoice:, add_on:, invoice_display_name: "Priority Support", amount_cents: 2_000,
        amount_currency: "USD")
    end
    let(:uncredited_fee) { create_product_fee(product:, amount_cents: 20_000, invoice_display_name: "Uncredited Package") }
    let(:credit_note) do
      create(:credit_note, organization:, customer:, invoice:, number: "CN-MIXED", total_amount_currency: "USD",
        total_amount_cents: 700, taxes_amount_cents: 0, credit_amount_currency: "USD", credit_amount_cents: 700)
    end

    before do
      credit(fee, 500)
      credit(add_on_fee, 200)
      uncredited_fee
    end

    it "keeps both summary entries while limiting Details to credited product fees" do
      document = rendered_document
      summary_text = document.css("table.document-table--summary").text.squish
      details_text = document.css(".details-page").text.squish

      expect(document.css("table.document-table--summary tbody tr").last.css("td").all? { it["class"].split.include?("cell--at-end") }).to be(true)
      expect(summary_text).to include("Export Package", "$5.00", "Priority Support", "$2.00")
      expect(details_text).to include("Data Export", "$5.00")
      expect(details_text).not_to include("Priority Support", "Uncredited Package", "$100.00", "$200.00")
    end
  end

  context "with many credited product rows" do
    let(:credit_note) do
      create(:credit_note, organization:, customer:, invoice:, number: "CN-LONG", total_amount_currency: "USD",
        total_amount_cents: 2_500, taxes_amount_cents: 0, credit_amount_currency: "USD", credit_amount_cents: 2_500)
    end

    before do
      Array.new(25) do |index|
        item_product = create(:product, organization:, product_category: category, name: "Product #{index}")
        item_fee = create_product_fee(product: item_product, amount_cents: 100,
          invoice_display_name: "Credit row #{index}")
        credit(item_fee, 100)
      end
    end

    it "renders all products and credited amounts on the Details page" do
      document = rendered_document
      detail_rows = document.css(".details-page tr.row--segment")
      product_names = document.css(".details-page tr.row--product .document-heading-label").map { |cell| cell.text.squish }
      amounts = detail_rows.map { |row| row.css("td").last.text.squish }

      expect(product_names).to match_array(Array.new(25) { |index| "Product #{index}" })
      expect(detail_rows.map { |row| row.css("td").first.text.squish }).to eq(Array.new(25, "From 1 Oct to 31 Oct 2026"))
      expect(amounts).to eq(Array.new(25, "$1.00"))
    end
  end
end
