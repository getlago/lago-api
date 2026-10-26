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
    create(:invoice, organization:, billing_entity:, customer:, invoice_type:, number: "INV-001", self_billed:, prepaid_credit_amount_cents:)
  end
  let(:invoice_type) { :contract }
  let(:self_billed) { false }
  let(:prepaid_credit_amount_cents) { 0 }
  let(:pay_in_advance) { false }
  let(:event_transaction_id) { nil }
  let(:contract) { create(:contract, organization:, customer:, name: "Platform") }
  let(:category) { create(:product_category, organization:, name: "Infrastructure", invoice_display_name: nil) }
  let(:product) { create(:product, organization:, product_category: category, name: "Compute", invoice_display_name: nil) }
  let(:rate_card) { create(:rate_card, organization:, product:) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }

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
      rate_card_rate: create(:rate_card_rate, organization:, rate_card: contract_rate_card.rate_card),
      amount_cents: 2_800,
      amount_currency: invoice.currency,
      units: 280,
      precise_unit_amount: 0.1,
      pay_in_advance:,
      pay_in_advance_event_transaction_id: event_transaction_id,
      properties: {"from_datetime" => "2026-10-01T00:00:00Z", "to_datetime" => "2026-10-31T23:59:59Z"}
    )
  end

  it "renders the summary with one line per category" do
    expect(rendered_text).to include("Description Amount Infrastructure")
  end

  it "renders the details page per contract, down to the billing period" do
    expect(rendered_text).to include("Details Platform - Invoice INV-001")
    expect(rendered_text).to include("Compute €28.00 From 1 Oct to 31 Oct 2026 280")
  end

  it "bills from the billing entity to the customer" do
    expect(rendered_text).to match(/From Hooli.*Bill to Pied Piper/)
  end

  it "shows the payment due date" do
    invoice.update!(payment_due_date: Date.new(2026, 11, 15))

    expect(rendered_text).to include("Due date #{I18n.l(Date.new(2026, 11, 15), format: :default)}")
  end

  it "shows the snapshotted payment term" do
    invoice.update!(payment_term: {"term_type" => "end_of_month"})

    expect(rendered_text).to include("Payment term Due at end of month")
  end

  context "when the invoice bills charges paid in advance" do
    let(:invoice_type) { :advance_charges }

    it "shows the total as already paid, with nothing due" do
      expect(rendered_text).to match(/Already paid \S+/)
      expect(rendered_text).not_to include("Amount due")
      expect(rendered_text).not_to include("Due date")
    end
  end

  context "when the invoice is partly paid with prepaid credits" do
    let(:prepaid_credit_amount_cents) { 500 }

    it "shows the deduction in the totals" do
      expect(rendered_text).to match(/Prepaid credits -\S+5\.00/)
    end
  end

  context "when the prepaid credits are split between free and purchased credits" do
    before { invoice.update!(prepaid_credit_amount_cents: 500, prepaid_granted_credit_amount_cents: 300, prepaid_purchased_credit_amount_cents: 200) }

    it "shows each kind of credit on its own line" do
      expect(rendered_text).to match(/Free credits -\S+3\.00 Prepaid credits -\S+2\.00/)
    end
  end

  context "when a coupon applies to the invoice" do
    let(:coupon) { create(:coupon, organization:, name: "Launch", amount_cents: 300) }

    before do
      applied_coupon = create(:applied_coupon, organization:, customer:, coupon:, amount_cents: 300)
      create(:credit, invoice:, applied_coupon:, amount_cents: 300)
    end

    it "deducts it before the subtotal" do
      expect(rendered_text).to match(/Launch \(\S+3\.00\) -\S+3\.00 Subtotal/)
    end
  end

  context "when credit notes are applied to the invoice" do
    before { invoice.update!(credit_notes_amount_cents: 400) }

    it "shows the deduction in the totals" do
      expect(rendered_text).to match(/Credit notes -\S+4\.00/)
    end
  end

  context "when a tax applies to the whole invoice" do
    before { create(:invoice_applied_tax, invoice:, tax_code: "reverse_charge") }

    it "names the tax without a rate or amount" do
      expect(rendered_text).to include("Reverse charge - Tax liability shifted to customer")
      expect(rendered_text).not_to include("VAT (20")
    end
  end

  context "when the billing entity manages EU taxes and the customer is reverse charged" do
    before do
      billing_entity.update!(eu_tax_management: true)
      create(:invoice_applied_tax, invoice:, tax_code: "lago_eu_reverse_charge")
    end

    it "renders the reverse charge mention" do
      expect(rendered_text).to include("Reverse charge - Tax liability shifted to customer.")
    end
  end

  context "when the invoice bills a single fee for its period in advance" do
    let(:pay_in_advance) { true }

    it "keeps the summary and the details page" do
      expect(rendered_text).to include("Description Amount Infrastructure")
      expect(rendered_text).to include("Details Platform")
    end
  end

  context "when the invoice bills a single fee on event reception" do
    let(:pay_in_advance) { true }
    let(:event_transaction_id) { "evt-1" }

    it "replaces the summary with the fee details and omits the details page" do
      expect(rendered_text).to include("Description Quantity Unit price Amount Infrastructure")
      expect(rendered_text).to match(/From 1 Oct to 31 Oct 2026 280 .*Subtotal/)
      expect(rendered_text).not_to include("Description Amount Infrastructure")
      expect(rendered_text).not_to include("Details Platform")
    end
  end

  context "when the invoice is self billed" do
    let(:self_billed) { true }

    it "swaps the issuer and the recipient" do
      expect(rendered_text).to match(/From Pied Piper.*Bill to Hooli/)
    end

    it "replaces the billing entity footer with the self-billing mention" do
      expect(rendered_text).to include("This self-billing invoice was issued by the client on behalf of the partner")
      expect(rendered_text).not_to include("Hooli footer")
    end
  end
end
