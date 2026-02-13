# frozen_string_literal: true

require "rails_helper"

# This spec relies on `rspec-snapshot` gem (https://github.com/levinmr/rspec-snapshot) in order to serialize and compare
# the rendered invoice HTML.
#
# To update a snapshot, either delete it, or run the tests with `UPDATE_SNAPSHOTS=true` environment variable.

RSpec.describe "templates/invoices/v4/self_billed.slim" do
  subject(:rendered_template) do
    Slim::Template.new(template, 1, pretty: true).render(invoice)
  end

  let(:template) { Rails.root.join("app/views/templates/invoices/v4/self_billed.slim") }

  let(:organization) { create(:organization, :with_static_values) }
  let(:billing_entity) { organization.default_billing_entity }
  let(:customer) { create(:customer, :with_static_values, organization:) }

  before do
    I18n.locale = :en
  end

  context "with one-off invoice" do
    let(:add_on) { create(:add_on, organization:, name: "Partner Commission") }

    let(:invoice) do
      create(
        :invoice,
        :self_billed,
        customer:,
        organization:,
        number: "LAGO-202509-SB-001",
        payment_due_date: Date.parse("2025-09-15"),
        issuing_date: Date.parse("2025-09-01"),
        invoice_type: :one_off,
        total_amount_cents: 50000,
        currency: "USD",
        fees_amount_cents: 50000,
        sub_total_excluding_taxes_amount_cents: 50000,
        sub_total_including_taxes_amount_cents: 50000,
        coupons_amount_cents: 0
      )
    end

    let(:add_on_fee) do
      create(
        :one_off_fee,
        invoice:,
        add_on:,
        amount_cents: 50000,
        amount_currency: "USD",
        units: 1,
        unit_amount_cents: 50000,
        invoice_display_name: "Partner Commission",
        description: "Monthly partner commission"
      )
    end

    before { add_on_fee }

    it "renders correctly" do
      expect(rendered_template).to match_html_snapshot
    end
  end

  context "with subscription invoice" do
    let(:plan) do
      create(
        :plan,
        organization:,
        interval: "monthly",
        pay_in_advance: false,
        invoice_display_name: "Partner Plan"
      )
    end

    let(:subscription) do
      create(:subscription, customer:, plan:, status: "active")
    end

    let(:invoice) do
      create(
        :invoice,
        :self_billed,
        customer:,
        organization:,
        number: "LAGO-202509-SB-002",
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

    let(:subscription_fee) do
      create(
        :fee,
        invoice:,
        subscription:,
        fee_type: :subscription,
        amount_cents: 10000,
        amount_currency: "USD",
        units: 1,
        invoice_display_name: "Partner Plan - Monthly",
        properties: {
          "from_datetime" => "2025-09-01 00:00:00",
          "to_datetime" => "2025-09-30 23:59:59",
          "charges_from_datetime" => "2025-09-01 00:00:00",
          "charges_to_datetime" => "2025-09-30 23:59:59"
        }
      )
    end

    before do
      invoice_subscription
      subscription_fee
    end

    it "renders correctly" do
      expect(rendered_template).to match_html_snapshot
    end
  end

  context "with credit invoice" do
    let(:plan) do
      create(
        :plan,
        organization:,
        interval: "monthly",
        pay_in_advance: false,
        invoice_display_name: "Partner Plan"
      )
    end

    let(:subscription) do
      create(:subscription, customer:, plan:, status: "active")
    end

    let(:wallet) { create(:wallet, customer:, balance_cents: 100000, credits_balance: 1000.0) }

    let(:wallet_transaction) do
      create(
        :wallet_transaction,
        wallet:,
        transaction_type: "inbound",
        amount: 500.0,
        credit_amount: 500.0,
        status: "settled",
        name: "Prepaid Credits"
      )
    end

    let(:invoice) do
      create(
        :invoice,
        :self_billed,
        :credit,
        customer:,
        organization:,
        number: "LAGO-202509-SB-003",
        payment_due_date: Date.parse("2025-09-15"),
        issuing_date: Date.parse("2025-09-01"),
        total_amount_cents: 50000,
        currency: "USD",
        fees_amount_cents: 50000,
        sub_total_excluding_taxes_amount_cents: 50000,
        sub_total_including_taxes_amount_cents: 50000,
        coupons_amount_cents: 0
      )
    end

    let(:credit_fee) do
      create(
        :credit_fee,
        invoice:,
        wallet_transaction:,
        amount_cents: 50000,
        amount_currency: "USD",
        units: 500,
        invoice_display_name: "Prepaid Credits"
      )
    end

    before do
      credit_fee
    end

    it "renders correctly" do
      expect(rendered_template).to match_html_snapshot
    end
  end

  context "with taxes applied" do
    let(:add_on) { create(:add_on, organization:, name: "Commission") }
    let(:tax) { create(:tax, organization:, name: "VAT", rate: 20.0) }

    let(:invoice) do
      create(
        :invoice,
        :self_billed,
        customer:,
        organization:,
        number: "LAGO-202509-SB-004",
        payment_due_date: Date.parse("2025-09-15"),
        issuing_date: Date.parse("2025-09-01"),
        invoice_type: :one_off,
        total_amount_cents: 60000,
        currency: "USD",
        fees_amount_cents: 50000,
        taxes_amount_cents: 10000,
        sub_total_excluding_taxes_amount_cents: 50000,
        sub_total_including_taxes_amount_cents: 60000,
        coupons_amount_cents: 0
      )
    end

    let(:add_on_fee) do
      create(
        :one_off_fee,
        invoice:,
        add_on:,
        amount_cents: 50000,
        amount_currency: "USD",
        units: 1,
        unit_amount_cents: 50000,
        taxes_amount_cents: 10000,
        invoice_display_name: "Commission"
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
        amount_cents: 10000,
        amount_currency: "USD",
        taxable_base_amount_cents: 50000,
        fees_amount_cents: 50000
      )
    end

    before do
      add_on_fee
      applied_tax
    end

    it "renders correctly" do
      expect(rendered_template).to match_html_snapshot
    end
  end
end
