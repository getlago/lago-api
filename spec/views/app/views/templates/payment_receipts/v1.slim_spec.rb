# frozen_string_literal: true

require "rails_helper"

RSpec.describe "templates/payment_receipts/v1.slim" do
  subject(:rendered_template) do
    Slim::Template.new(template, 1, pretty: true).render(payment_receipt)
  end

  let(:template) { Rails.root.join("app/views/templates/payment_receipts/v1.slim") }
  let(:organization) { create(:organization, :with_static_values) }
  let(:billing_entity) { organization.default_billing_entity }
  let(:customer) { create(:customer, :with_static_values, organization:) }

  before do
    I18n.locale = :en
  end

  context "when payable invoice is progressive_billing with prepaid credits" do
    let(:billable_metric) { create(:billable_metric, organization:) }
    let(:plan) { create(:plan, organization:, interval: "monthly", pay_in_advance: false, invoice_display_name: "Progressive Billing Plan") }
    let(:charge) { create(:standard_charge, plan:, billable_metric:, invoice_display_name: "Usage Charge") }
    let(:subscription) { create(:subscription, customer:, plan:, status: "active") }
    let(:wallet) { create(:wallet, customer:, organization:, rate_amount: BigDecimal("1.0"), balance_currency: "USD") }
    let(:wallet_transaction) { create(:wallet_transaction, wallet:, invoice:, credit_amount: BigDecimal("5.0"), amount: BigDecimal("5.0")) }
    let(:applied_usage_threshold) { nil }

    let(:invoice) do
      create(
        :invoice,
        customer:,
        organization:,
        billing_entity:,
        number: "LAGO-202509-PR-001",
        payment_due_date: Date.parse("2025-09-15"),
        issuing_date: Date.parse("2025-09-15"),
        invoice_type: :progressive_billing,
        total_amount_cents: 9500,
        total_paid_amount_cents: 9500,
        currency: "USD",
        fees_amount_cents: 10000,
        sub_total_excluding_taxes_amount_cents: 10000,
        sub_total_including_taxes_amount_cents: 10000,
        prepaid_credit_amount_cents: 500,
        prepaid_granted_credit_amount_cents: 200,
        prepaid_purchased_credit_amount_cents: 300
      )
    end

    let(:invoice_subscription) do
      create(
        :invoice_subscription,
        invoice:,
        subscription:,
        from_datetime: Time.zone.parse("2025-09-01 00:00:00"),
        to_datetime: Time.zone.parse("2025-09-30 23:59:59"),
        charges_from_datetime: Time.zone.parse("2025-09-01 00:00:00"),
        charges_to_datetime: Time.zone.parse("2025-09-15 23:59:59"),
        timestamp: Time.zone.parse("2025-09-15 12:00:00")
      )
    end

    let(:charge_fee) do
      create(
        :charge_fee,
        invoice:,
        subscription:,
        charge:,
        amount_cents: 10000,
        amount_currency: "USD",
        units: 100,
        unit_amount_cents: 100,
        precise_unit_amount: 1.00,
        invoice_display_name: "Usage Charge Fee",
        properties: {
          "timestamp" => "2025-09-15 12:00:00",
          "charges_from_datetime" => "2025-09-01 00:00:00",
          "charges_to_datetime" => "2025-09-15 23:59:59"
        }
      )
    end

    let(:payment) do
      create(
        :payment,
        payable: invoice,
        organization:,
        customer:,
        amount_cents: 9500,
        amount_currency: "USD",
        status: "succeeded",
        payable_payment_status: "succeeded"
      )
    end

    let(:payment_receipt) do
      create(:payment_receipt, payment:, organization:, billing_entity:, number: "RCT-202509-001")
    end

    before do
      invoice_subscription
      charge_fee
      wallet_transaction
      applied_usage_threshold
    end

    it "renders without the reached usage threshold line" do
      expect(rendered_template).not_to include("This progressive billing is generated because your cumulative usage has reached")
    end
  end

  context "when payable invoice is a product catalog invoice" do
    let(:rendered_text) do
      document = Nokogiri::HTML(rendered_template)
      document.css("style").remove
      document.xpath("//body//text()").map(&:text).join(" ").squish
    end

    let(:invoice_type) { :contract }
    let(:invoice) do
      create(
        :invoice,
        customer:,
        organization:,
        billing_entity:,
        invoice_type:,
        number: "LAGO-202610-001",
        currency: "EUR",
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
    let(:payment) do
      create(:payment, payable: invoice, organization:, customer:, amount_cents: 2_800, amount_currency: "EUR", status: "succeeded", payable_payment_status: "succeeded")
    end
    let(:payment_receipt) { create(:payment_receipt, payment:, organization:, billing_entity:, number: "RCT-202610-001") }
    let(:product_filter) { nil }

    before do
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
        amount_currency: "EUR",
        units: 280,
        precise_unit_amount: 0.1,
        properties: {"from_datetime" => "2026-10-01T00:00:00Z", "to_datetime" => "2026-10-31T23:59:59Z"}
      )
    end

    it "lists the items by product category" do
      expect(rendered_text).to include("Item Amount Infrastructure €28.00")
    end

    it "ends the totals with the amount due" do
      expect(rendered_text).to include("Subtotal (excl. tax) €28.00 Total €28.00 Amount due €0.00")
    end

    it "details each contract after the summary, down to the billing period" do
      expect(rendered_text).to include("Details Platform - Invoice LAGO-202610-001")
      expect(rendered_text).to include("Infrastructure €28.00 Compute €28.00 From 1 Oct to 31 Oct 2026 280")
    end

    context "when the fee is billed on a product filter" do
      let(:product_filter) { create(:product_filter, organization:, product:, name: "EU", invoice_display_name: nil) }

      it "details the fee under its filter" do
        expect(rendered_text).to include("Compute €28.00 EU From 1 Oct to 31 Oct 2026 280")
      end
    end

    context "when the invoice bills fees paid in advance" do
      let(:invoice_type) { :advance_charges }

      it "lists the items and shows the total as already paid, with nothing due" do
        expect(rendered_text).to include("Item Amount Infrastructure €28.00")
        expect(rendered_text).to include("Subtotal (excl. tax) €28.00 Already paid €28.00")
        expect(rendered_text).not_to include("Amount due")
      end
    end
  end
end
