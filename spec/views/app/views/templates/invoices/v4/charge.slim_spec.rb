# frozen_string_literal: true

require "rails_helper"

# This spec relies on `rspec-snapshot` gem (https://github.com/levinmr/rspec-snapshot) in order to serialize and compare
# the rendered invoice HTML.
#
# To update a snapshot, either delete it, or run the tests with `UPDATE_SNAPSHOTS=true` environment variable.

RSpec.describe "templates/invoices/v4/charge.slim" do
  subject(:rendered_template) do
    Slim::Template.new(template, 1, pretty: true).render(invoice)
  end

  let(:template) { Rails.root.join("app/views/templates/invoices/v4/charge.slim") }

  let(:organization) { create(:organization, :with_static_values) }
  let(:billing_entity) { organization.default_billing_entity }
  let(:customer) { create(:customer, :with_static_values, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:) }

  let(:plan) do
    create(
      :plan,
      organization:,
      interval: "monthly",
      pay_in_advance: false,
      invoice_display_name: "Monthly Plan"
    )
  end

  let(:subscription) do
    create(:subscription, customer:, plan:, status: "active")
  end

  let(:invoice) do
    create(
      :invoice,
      customer:,
      organization:,
      number: "LAGO-202509-CH-001",
      payment_due_date: Date.parse("2025-09-15"),
      issuing_date: Date.parse("2025-09-01"),
      invoice_type: :subscription,
      total_amount_cents: 10000,
      currency: "USD",
      fees_amount_cents: 10000,
      sub_total_excluding_taxes_amount_cents: 10000,
      sub_total_including_taxes_amount_cents: 10000,
      coupons_amount_cents: 0
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
      charges_to_datetime: Time.zone.parse("2025-09-30 23:59:59"),
      timestamp: Time.zone.parse("2025-09-01 00:00:00")
    )
  end

  before do
    I18n.locale = :en
    invoice_subscription
  end

  context "with a single standard charge fee" do
    let(:charge) do
      create(:standard_charge, :pay_in_advance, plan:, billable_metric:)
    end

    let(:charge_fee) do
      create(
        :charge_fee,
        invoice:,
        charge:,
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

    before { charge_fee }

    it "renders charge fee with item details" do
      expect(rendered_template).to include("API Calls")
      expect(rendered_template).to match_html_snapshot
    end
  end

  context "with multiple charge fees" do
    let(:charge_1) do
      create(:standard_charge, :pay_in_advance, plan:, billable_metric:)
    end

    let(:charge_2) do
      create(:standard_charge, :pay_in_advance, plan:, billable_metric:)
    end

    let(:charge_fee_1) do
      create(
        :charge_fee,
        invoice:,
        charge: charge_1,
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

    let(:charge_fee_2) do
      create(
        :charge_fee,
        invoice:,
        charge: charge_2,
        subscription:,
        pay_in_advance: true,
        amount_cents: 3000,
        amount_currency: "USD",
        units: 5,
        unit_amount_cents: 600,
        precise_unit_amount: 6.00,
        invoice_display_name: "Storage GB",
        properties: {
          "from_datetime" => "2025-09-01 00:00:00",
          "to_datetime" => "2025-09-30 23:59:59",
          "charges_from_datetime" => "2025-09-01 00:00:00",
          "charges_to_datetime" => "2025-09-30 23:59:59"
        }
      )
    end

    before do
      charge_fee_1
      charge_fee_2
    end

    it "renders all charge fees" do
      expect(rendered_template).to include("API Calls")
      expect(rendered_template).to include("Storage GB")
      expect(rendered_template).to match_html_snapshot
    end
  end

  context "with percentage charge with basic rate" do
    let(:percentage_charge) do
      create(:percentage_charge, :pay_in_advance, plan:, billable_metric:)
    end

    let(:percentage_fee) do
      create(
        :charge_fee,
        invoice:,
        charge: percentage_charge,
        subscription:,
        pay_in_advance: true,
        amount_cents: 5550,
        amount_currency: "USD",
        units: 100,
        unit_amount_cents: 55,
        precise_unit_amount: 0.555,
        invoice_display_name: "Transaction Fee",
        amount_details: {
          "paid_units" => "100",
          "rate" => "5.55",
          "per_unit_total_amount" => "55.50"
        },
        properties: {
          "from_datetime" => "2025-09-01 00:00:00",
          "to_datetime" => "2025-09-30 23:59:59",
          "charges_from_datetime" => "2025-09-01 00:00:00",
          "charges_to_datetime" => "2025-09-30 23:59:59"
        }
      )
    end

    before { percentage_fee }

    it "renders percentage charge with rate" do
      expect(rendered_template).to include("Transaction Fee")
      expect(rendered_template).to include("5.55%")
      expect(rendered_template).to match_html_snapshot
    end
  end

  context "with percentage charge with detailed breakdown" do
    let(:percentage_charge) do
      create(:percentage_charge, :pay_in_advance, plan:, billable_metric:)
    end

    let(:percentage_fee) do
      create(
        :charge_fee,
        invoice:,
        charge: percentage_charge,
        subscription:,
        pay_in_advance: true,
        amount_cents: 7550,
        amount_currency: "USD",
        units: 100,
        events_count: 50,
        invoice_display_name: "Payment Processing Fee",
        amount_details: {
          "paid_units" => "100",
          "rate" => "5.55",
          "per_unit_total_amount" => "55.50",
          "fixed_fee_unit_amount" => "0.20",
          "fixed_fee_total_amount" => "20.00",
          "min_max_adjustment_total_amount" => "0.00",
          "per_transaction_min_amount" => "0.00",
          "per_transaction_max_amount" => "0.00"
        },
        properties: {
          "from_datetime" => "2025-09-01 00:00:00",
          "to_datetime" => "2025-09-30 23:59:59",
          "charges_from_datetime" => "2025-09-01 00:00:00",
          "charges_to_datetime" => "2025-09-30 23:59:59"
        }
      )
    end

    before { percentage_fee }

    it "renders percentage charge with breakdown details" do
      expect(rendered_template).to include("Payment Processing Fee")
      expect(rendered_template).to match_html_snapshot
    end
  end

  context "with prorated charge" do
    let(:recurring_billable_metric) { create(:unique_count_billable_metric, :recurring, organization:) }

    let(:prorated_charge) do
      create(:standard_charge, :pay_in_advance, plan:, billable_metric: recurring_billable_metric, prorated: true)
    end

    let(:prorated_fee) do
      create(
        :charge_fee,
        invoice:,
        charge: prorated_charge,
        subscription:,
        pay_in_advance: true,
        amount_cents: 2500,
        amount_currency: "USD",
        units: 5,
        unit_amount_cents: 500,
        precise_unit_amount: 5.00,
        invoice_display_name: "Prorated Seats",
        properties: {
          "from_datetime" => "2025-09-15 00:00:00",
          "to_datetime" => "2025-09-30 23:59:59",
          "charges_from_datetime" => "2025-09-15 00:00:00",
          "charges_to_datetime" => "2025-09-30 23:59:59"
        }
      )
    end

    before { prorated_fee }

    it "renders prorated charge with proration details" do
      expect(rendered_template).to include("Prorated Seats")
      expect(rendered_template).to match_html_snapshot
    end
  end

  context "with non-invoiceable charge" do
    let(:non_invoiceable_charge) do
      create(:standard_charge, :pay_in_advance, plan:, billable_metric:, invoiceable: false)
    end

    let(:non_invoiceable_fee) do
      create(
        :charge_fee,
        invoice:,
        charge: non_invoiceable_charge,
        subscription:,
        pay_in_advance: true,
        succeeded_at: Time.zone.parse("2025-09-05 10:30:00"),
        amount_cents: 1000,
        amount_currency: "USD",
        units: 1,
        unit_amount_cents: 1000,
        precise_unit_amount: 10.00,
        invoice_display_name: "One-time Setup",
        properties: {
          "from_datetime" => "2025-09-01 00:00:00",
          "to_datetime" => "2025-09-30 23:59:59",
          "charges_from_datetime" => "2025-09-01 00:00:00",
          "charges_to_datetime" => "2025-09-30 23:59:59"
        }
      )
    end

    before { non_invoiceable_fee }

    it "renders non-invoiceable charge with succeeded date" do
      expect(rendered_template).to include("One-time Setup")
      expect(rendered_template).to include("Sep 05, 2025")
      expect(rendered_template).to match_html_snapshot
    end
  end

  context "with charge filter" do
    let(:charge) do
      create(:standard_charge, :pay_in_advance, plan:, billable_metric:)
    end

    let(:charge_filter) do
      create(:charge_filter, charge:)
    end

    let(:filtered_fee) do
      create(
        :charge_fee,
        invoice:,
        charge:,
        charge_filter:,
        subscription:,
        pay_in_advance: true,
        amount_cents: 2000,
        amount_currency: "USD",
        units: 4,
        unit_amount_cents: 500,
        precise_unit_amount: 5.00,
        invoice_display_name: "Filtered Charge",
        properties: {
          "from_datetime" => "2025-09-01 00:00:00",
          "to_datetime" => "2025-09-30 23:59:59",
          "charges_from_datetime" => "2025-09-01 00:00:00",
          "charges_to_datetime" => "2025-09-30 23:59:59"
        }
      )
    end

    before { filtered_fee }

    it "renders charge with filter" do
      expect(rendered_template).to include("Filtered Charge")
      expect(rendered_template).to match_html_snapshot
    end
  end

  context "with coupon applied" do
    let(:charge) do
      create(:standard_charge, :pay_in_advance, plan:, billable_metric:)
    end

    let(:charge_fee) do
      create(
        :charge_fee,
        invoice:,
        charge:,
        subscription:,
        pay_in_advance: true,
        amount_cents: 5000,
        amount_currency: "USD",
        units: 10,
        unit_amount_cents: 500,
        precise_unit_amount: 5.00,
        invoice_display_name: "Charge with Coupon",
        properties: {
          "from_datetime" => "2025-09-01 00:00:00",
          "to_datetime" => "2025-09-30 23:59:59",
          "charges_from_datetime" => "2025-09-01 00:00:00",
          "charges_to_datetime" => "2025-09-30 23:59:59"
        }
      )
    end

    let(:coupon) { create(:coupon, organization:, name: "20% Discount") }
    let(:applied_coupon) { create(:applied_coupon, coupon:, customer:) }
    let(:credit) do
      create(
        :credit,
        invoice:,
        applied_coupon:,
        amount_cents: 1000,
        amount_currency: "USD"
      )
    end

    let(:invoice) do
      create(
        :invoice,
        customer:,
        organization:,
        number: "LAGO-202509-CH-002",
        payment_due_date: Date.parse("2025-09-15"),
        issuing_date: Date.parse("2025-09-01"),
        invoice_type: :subscription,
        total_amount_cents: 4000,
        currency: "USD",
        fees_amount_cents: 5000,
        coupons_amount_cents: 1000,
        sub_total_excluding_taxes_amount_cents: 4000,
        sub_total_including_taxes_amount_cents: 4000
      )
    end

    before do
      charge_fee
      credit
    end

    it "renders with coupon discount" do
      expect(rendered_template).to include("20% Discount")
      expect(rendered_template).to match_html_snapshot
    end
  end

  context "with taxes applied" do
    let(:charge) do
      create(:standard_charge, :pay_in_advance, plan:, billable_metric:)
    end

    let(:tax) { create(:tax, organization:, name: "VAT", rate: 20.0) }

    let(:charge_fee) do
      create(
        :charge_fee,
        invoice:,
        charge:,
        subscription:,
        pay_in_advance: true,
        amount_cents: 5000,
        amount_currency: "USD",
        units: 10,
        unit_amount_cents: 500,
        precise_unit_amount: 5.00,
        taxes_amount_cents: 1000,
        invoice_display_name: "Taxable Charge",
        properties: {
          "from_datetime" => "2025-09-01 00:00:00",
          "to_datetime" => "2025-09-30 23:59:59",
          "charges_from_datetime" => "2025-09-01 00:00:00",
          "charges_to_datetime" => "2025-09-30 23:59:59"
        }
      )
    end

    let(:invoice) do
      create(
        :invoice,
        customer:,
        organization:,
        number: "LAGO-202509-CH-003",
        payment_due_date: Date.parse("2025-09-15"),
        issuing_date: Date.parse("2025-09-01"),
        invoice_type: :subscription,
        total_amount_cents: 6000,
        currency: "USD",
        fees_amount_cents: 5000,
        taxes_amount_cents: 1000,
        coupons_amount_cents: 0,
        sub_total_excluding_taxes_amount_cents: 5000,
        sub_total_including_taxes_amount_cents: 6000
      )
    end

    let(:applied_tax) do
      create(
        :invoice_applied_tax,
        invoice:,
        tax:,
        tax_name: "VAT",
        tax_code: "vat",
        tax_rate: 20.0,
        amount_cents: 1000,
        amount_currency: "USD",
        taxable_base_amount_cents: 5000,
        fees_amount_cents: 5000
      )
    end

    before do
      charge_fee
      applied_tax
    end

    it "renders with tax breakdown" do
      expect(rendered_template).to include("Taxable Charge")
      expect(rendered_template).to include("VAT")
      expect(rendered_template).to include("20")
      expect(rendered_template).to match_html_snapshot
    end
  end
end
