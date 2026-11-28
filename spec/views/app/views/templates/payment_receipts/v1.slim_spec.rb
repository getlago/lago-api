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

  context "when the payable invoice has a hidden $0 subscription fee alone in its billing period" do
    let(:billable_metric) { create(:billable_metric, organization:) }
    let(:plan) { create(:plan, organization:, interval: "monthly", pay_in_advance: false, amount_cents: 0, invoice_display_name: "Seats Plan") }
    let(:charge) { create(:standard_charge, plan:, billable_metric:, pay_in_advance: true, invoice_display_name: "Seats") }
    let(:subscription) { create(:subscription, customer:, plan:, status: "active") }

    let(:invoice) do
      create(
        :invoice,
        customer:,
        organization:,
        billing_entity:,
        number: "LAGO-202610-001",
        payment_due_date: Date.parse("2026-10-03"),
        issuing_date: Date.parse("2026-10-03"),
        invoice_type: :subscription,
        total_amount_cents: 18000,
        total_paid_amount_cents: 18000,
        currency: "USD",
        fees_amount_cents: 18000,
        sub_total_excluding_taxes_amount_cents: 18000,
        sub_total_including_taxes_amount_cents: 18000
      )
    end

    # The subscription fee is billed in arrears for the past period, the seats charge in advance for the next one
    let(:invoice_subscription) do
      create(
        :invoice_subscription,
        invoice:,
        subscription:,
        from_datetime: Time.zone.parse("2026-09-03 00:00:00"),
        to_datetime: Time.zone.parse("2026-10-02 23:59:59"),
        charges_from_datetime: Time.zone.parse("2026-10-03 00:00:00"),
        charges_to_datetime: Time.zone.parse("2026-11-02 23:59:59"),
        timestamp: Time.zone.parse("2026-10-03 00:00:00")
      )
    end

    let(:subscription_fee) do
      create(
        :fee,
        invoice:,
        subscription:,
        fee_type: :subscription,
        amount_cents: 0,
        amount_currency: "USD",
        units: 1,
        unit_amount_cents: 0,
        precise_unit_amount: 0,
        invoice_display_name: nil,
        properties: {
          from_datetime: "2026-09-03 00:00:00",
          to_datetime: "2026-10-02 23:59:59"
        }
      )
    end

    let(:seats_fee) do
      create(
        :charge_fee,
        invoice:,
        subscription:,
        charge:,
        pay_in_advance: true,
        amount_cents: 18000,
        amount_currency: "USD",
        units: 12,
        unit_amount_cents: 1500,
        precise_unit_amount: 15,
        total_aggregated_units: 12,
        invoice_display_name: "Seats",
        properties: {
          "timestamp" => "2026-10-03 00:00:00",
          "charges_from_datetime" => "2026-10-03 00:00:00",
          "charges_to_datetime" => "2026-11-02 23:59:59"
        }
      )
    end

    let(:payment) do
      create(
        :payment,
        payable: invoice,
        organization:,
        customer:,
        amount_cents: 18000,
        amount_currency: "USD",
        status: "succeeded",
        payable_payment_status: "succeeded"
      )
    end

    let(:payment_receipt) do
      create(:payment_receipt, payment:, organization:, billing_entity:, number: "RCT-202610-001")
    end

    before do
      invoice_subscription
      subscription_fee
      seats_fee
    end

    it "renders only the billing period of the displayed fees" do
      sections = Nokogiri::HTML(rendered_template).css(".invoice-resume > table.invoice-resume-table").map do |table|
        {heading: table.at_css("tr.first_child > td").text.strip, fees: table.css("tr.fee > td:first-child").map { it.text.strip }}
      end

      expect(sections).to eq([{heading: "Fees from Oct 03, 2026 to Nov 02, 2026", fees: ["Seats"]}])
      expect(rendered_template).not_to include("Fees from Sep 03, 2026 to Oct 02, 2026")
    end
  end

  context "with an advance_charges invoice" do
    let(:billable_metric) { create(:billable_metric, organization:) }
    let(:plan) { create(:plan, organization:, interval: "monthly", pay_in_advance: false, invoice_display_name: "Monthly Plan") }
    let(:subscription) { create(:subscription, customer:, plan:, status: "active") }
    let(:voided_invoice_id) { nil }

    let(:invoice) do
      create(
        :invoice,
        customer:,
        organization:,
        billing_entity:,
        number: "LAGO-202509-CH-001",
        payment_due_date: Date.parse("2025-09-15"),
        issuing_date: Date.parse("2025-09-01"),
        invoice_type: :advance_charges,
        voided_invoice_id:,
        total_amount_cents: 5000,
        total_paid_amount_cents: 5000,
        currency: "USD",
        fees_amount_cents: 5000,
        sub_total_excluding_taxes_amount_cents: 5000,
        sub_total_including_taxes_amount_cents: 5000
      )
    end

    let(:payment) do
      create(
        :payment,
        payable: invoice,
        organization:,
        customer:,
        amount_cents: 5000,
        amount_currency: "USD",
        status: "succeeded",
        payable_payment_status: "succeeded"
      )
    end

    let(:payment_receipt) do
      create(:payment_receipt, payment:, organization:, billing_entity:, number: "RCT-202509-001")
    end

    let(:rendered_text) do
      document = Nokogiri::HTML(rendered_template)
      document.css("style").remove
      document.xpath("//body//text()").map(&:text).join(" ").squish
    end

    before do
      create(
        :charge_fee,
        invoice:,
        charge: create(:standard_charge, :pay_in_advance, plan:, billable_metric:),
        subscription:,
        pay_in_advance: true,
        amount_cents: 5000,
        amount_currency: "USD",
        units: 10,
        unit_amount_cents: 500,
        precise_unit_amount: 5.00,
        invoice_display_name: "API Calls",
        properties: {
          "from_datetime" => "2025-09-01 00:00:00",
          "to_datetime" => "2025-09-30 23:59:59",
          "charges_from_datetime" => "2025-09-01 00:00:00",
          "charges_to_datetime" => "2025-09-30 23:59:59"
        }
      )
    end

    it "renders the fees as already paid" do
      expect(rendered_text).to include("Already paid $50.00")
    end

    context "when it is regenerated from a voided invoice" do
      let(:voided_invoice_id) { create(:invoice, customer:, organization:, invoice_type: :advance_charges, status: :voided).id }

      it "renders the total like a regular invoice" do
        expect(rendered_text).to include("Total $50.00")
        expect(rendered_text).not_to include("Already paid")
      end
    end
  end
end
