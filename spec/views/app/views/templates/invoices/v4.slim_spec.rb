# frozen_string_literal: true

require "rails_helper"

# This spec relies on `rspec-snapshot` gem (https://github.com/levinmr/rspec-snapshot) in order to serialize and compare
# the rendered invoice HTML.
#
# To update a snapshot, either delete it, or run the tests with `UPDATE_SNAPSHOTS=true` environment variable.

RSpec.describe "templates/invoices/v4.slim", type: :view do
  subject(:rendered_template) do
    Slim::Template.new(template, 1, pretty: true).render(invoice)
  end

  let(:template) { Rails.root.join("app/views/templates/invoices/v4.slim") }
  let(:invoice) do
    build_stubbed(
      :invoice,
      :credit,
      organization: organization,
      billing_entity: billing_entity,
      customer: customer,
      number: "LAGO-202509-001",
      payment_due_date: Date.parse("2025-09-04"),
      issuing_date: Date.parse("2025-09-04"),
      total_amount_cents: 1050,
      currency: "USD",
      fees: [fee]
    )
  end
  # Static organization data for consistent rendering
  let(:organization) do
    build_stubbed(:organization, :with_static_values)
  end

  # Static billing entity data for consistent rendering
  let(:billing_entity) do
    build_stubbed(:billing_entity, :with_static_values, organization: organization)
  end
  # Static customer data
  let(:customer) do
    build_stubbed(:customer, :with_static_values, organization: organization)
  end

  # Static wallet data
  let(:wallet) do
    build_stubbed(
      :wallet,
      customer: customer,
      name: wallet_name,
      balance_currency: "USD",
      rate_amount: BigDecimal("1.0")
    )
  end

  # Static wallet transaction data
  let(:wallet_transaction) do
    build_stubbed(
      :wallet_transaction,
      wallet: wallet,
      credit_amount: BigDecimal("10.50"),
      amount: BigDecimal("10.50"),
      name: wallet_transaction_name
    )
  end
  let(:wallet_transaction_name) { nil }

  # Static fee data
  let(:fee) do
    build_stubbed(
      :fee,
      id: "87654321-0fed-cba9-8765-4321fedcba90",
      fee_type: :credit,
      invoiceable: wallet_transaction,
      amount_cents: 1050,
      amount_currency: "USD"
    )
  end

  let(:wallet_name) { "Premium Wallet" }

  before do
    # Set locale to ensure consistent translations
    I18n.locale = :en
  end

  context "when invoice_type is credit" do
    context "when wallet transaction has a name" do
      let(:wallet_transaction_name) { "Wallet Transaction Name" }

      it "renders correctly" do
        expect(rendered_template).to match_html_snapshot
      end
    end

    context "when wallet transaction has no name" do
      let(:wallet_transaction_name) { nil }

      context "when wallet has no name" do
        let(:wallet_name) { nil }

        it "renders correctly" do
          expect(rendered_template).to match_html_snapshot
        end
      end

      context "when wallet has a name" do
        let(:wallet_name) { "Premium Wallet" }

        it "renders correctly" do
          expect(rendered_template).to match_html_snapshot
        end
      end
    end
  end

  context "when invoice has fixed charge fees" do
    let(:organization) { create(:organization, :with_static_values) }
    let(:billing_entity) { create(:billing_entity, :with_static_values, organization: organization) }
    let(:customer) { create(:customer, :with_static_values, organization: organization, billing_entity: billing_entity) }

    let(:plan) do
      create(
        :plan,
        organization: organization,
        interval: "monthly",
        pay_in_advance: false,
        invoice_display_name: "Premium Plan"
      )
    end

    let(:add_on) do
      create(
        :add_on,
        organization: organization,
        name: "Setup Fee",
        invoice_display_name: "Setup Fee"
      )
    end

    let(:fixed_charge) do
      create(
        :fixed_charge,
        organization: organization,
        plan: plan,
        add_on: add_on,
        charge_model: "standard",
        pay_in_advance: false,
        prorated: false,
        units: 2,
        invoice_display_name: "Setup Fee",
        properties: {amount: "25.00"}
      )
    end

    let(:subscription) do
      create(
        :subscription,
        organization: organization,
        customer: customer,
        plan: plan,
        status: "active"
      )
    end

    let(:invoice) do
      create(
        :invoice,
        organization: organization,
        billing_entity: billing_entity,
        customer: customer,
        number: "LAGO-202509-001",
        payment_due_date: Date.parse("2025-09-04"),
        issuing_date: Date.parse("2025-09-04"),
        invoice_type: :subscription,
        total_amount_cents: 5000,
        currency: "USD",
        fees_amount_cents: 5000,
        sub_total_excluding_taxes_amount_cents: 5000,
        sub_total_including_taxes_amount_cents: 5000
      )
    end

    let(:invoice_subscription) do
      create(
        :invoice_subscription,
        invoice: invoice,
        subscription: subscription,
        organization: organization,
        from_datetime: Time.zone.parse("2025-08-01 00:00:00"),
        to_datetime: Time.zone.parse("2025-08-31 23:59:59"),
        charges_from_datetime: Time.zone.parse("2025-08-01 00:00:00"),
        charges_to_datetime: Time.zone.parse("2025-08-31 23:59:59"),
        fixed_charges_from_datetime: Time.zone.parse("2025-08-01 00:00:00"),
        fixed_charges_to_datetime: Time.zone.parse("2025-08-31 23:59:59"),
        timestamp: Time.zone.parse("2025-08-31 23:59:59")
      )
    end

    let(:fee) do
      create(
        :fee,
        invoice: invoice,
        subscription: subscription,
        fixed_charge: fixed_charge,
        fee_type: :fixed_charge,
        organization: organization,
        billing_entity: billing_entity,
        amount_cents: 5000,
        amount_currency: "USD",
        units: 2,
        unit_amount_cents: 2500,
        precise_unit_amount: 25.00,
        invoice_display_name: "Setup Fee",
        invoiceable: nil
      )
    end

    before do
      fee
      invoice_subscription
    end

    it "renders correctly" do
      expect(rendered_template).to match_html_snapshot
    end
  end
end
