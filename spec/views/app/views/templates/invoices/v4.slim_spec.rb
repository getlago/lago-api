# frozen_string_literal: true

require "rails_helper"

# This spec relies on `rspec-snapshot` gem (https://github.com/levinmr/rspec-snapshot) in order to serialize and compare
# the rendered invoice HTML.
#
# To update a snapshot, either delete it, or run the tests with `UPDATE_SNAPSHOTS=true` environment variable.

RSpec.describe "templates/invoices/v4.slim" do
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

  context "when invoice_type is subscription and plan is paid in arrears" do
    let(:organization) { create(:organization, :with_static_values) }
    let(:customer) { create(:customer, :with_static_values, organization:) }

    let(:plan) do
      create(
        :plan,
        organization:,
        interval: "monthly",
        invoice_display_name: "Pay in Arrears Premium Plan"
      )
    end

    let(:subscription) do
      create(:subscription, customer:, plan:, status: "active")
    end

    let(:invoice) do
      create(
        :invoice,
        customer:,
        number: "LAGO-202509-002",
        payment_due_date: Date.parse("2025-10-01"),
        issuing_date: Date.parse("2025-09-01"),
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
        invoice:,
        subscription:,
        from_datetime: Time.zone.parse("2025-08-01 00:00:00"),
        to_datetime: Time.zone.parse("2025-08-31 23:59:59"),
        charges_from_datetime: Time.zone.parse("2025-08-01 00:00:00"),
        charges_to_datetime: Time.zone.parse("2025-08-31 23:59:59"),
        fixed_charges_from_datetime: Time.zone.parse("2025-08-01 00:00:00"),
        fixed_charges_to_datetime: Time.zone.parse("2025-08-31 23:59:59"),
        timestamp: Time.zone.parse("2025-08-31 23:59:59")
      )
    end

    let(:subscription_fee) do
      create(
        :fee,
        invoice:,
        subscription:,
        fee_type: :subscription,
        amount_cents: 1500,
        amount_currency: "USD",
        units: 1,
        unit_amount_cents: 1500,
        precise_unit_amount: 15.00,
        invoice_display_name: "Pay in Arrears Subscription Fee",
        properties: {
          from_datetime: "2025-08-01 00:00:00",
          to_datetime: "2025-08-31 23:59:59"
        }
      )
    end

    let(:add_on) { create(:add_on, organization: organization) }

    # Pay in advance fees
    # 1. Standard model - not prorated
    let(:standard_fixed_charge) do
      create(:fixed_charge, :pay_in_advance, plan:, add_on:)
    end
    let(:standard_fixed_charge_fee) do
      create(
        :fixed_charge_fee,
        invoice:,
        fixed_charge: standard_fixed_charge,
        subscription:,
        pay_in_advance: true,
        amount_cents: 5000,
        amount_currency: "USD",
        units: 2,
        unit_amount_cents: 2500,
        precise_unit_amount: 25.00,
        invoice_display_name: "Standard Pay in Advance Fixed Charge Fee",
        properties: {
          fixed_charges_from_datetime: "2025-09-01 00:00:00",
          fixed_charges_to_datetime: "2025-09-30 23:59:59"
        }
      )
    end

    # 2. Standard model - prorated
    let(:standard_prorated_fixed_charge) do
      create(
        :fixed_charge,
        :pay_in_advance,
        plan:,
        add_on:,
        prorated: true
      )
    end
    let(:standard_prorated_fixed_charge_fee) do
      create(
        :fixed_charge_fee,
        invoice:,
        fixed_charge: standard_prorated_fixed_charge,
        subscription:,
        pay_in_advance: true,
        amount_cents: 5000,
        amount_currency: "USD",
        units: 0.5,
        unit_amount_cents: 10000,
        precise_unit_amount: 100.00,
        invoice_display_name: "Standard Pay in Advance Prorated Fixed Charge Fee",
        properties: {
          fixed_charges_from_datetime: "2025-09-01 00:00:00",
          fixed_charges_to_datetime: "2025-09-30 23:59:59"
        }
      )
    end

    # 3. Graduated model - not prorated
    let(:graduated_fixed_charge) do
      create(
        :fixed_charge,
        :graduated,
        :pay_in_advance,
        plan:,
        add_on:
      )
    end
    let(:graduated_fixed_charge_fee) do
      create(
        :fixed_charge_fee,
        invoice:,
        fixed_charge: graduated_fixed_charge,
        subscription:,
        pay_in_advance: true,
        amount_cents: 55500,
        amount_currency: "USD",
        units: 15,
        unit_amount_cents: 3700,
        precise_unit_amount: 37.00,
        invoice_display_name: "Graduated Pay in Advance Fixed Charge Fee",
        amount_details: {
          "graduated_ranges" => [
            {
              "from_value" => 0,
              "to_value" => 10,
              "units" => 10.0,
              "per_unit_amount" => "5.0",
              "per_unit_total_amount" => "50.0",
              "flat_unit_amount" => "200.0"
            },
            {
              "from_value" => 11,
              "to_value" => nil,
              "units" => 5.0,
              "per_unit_amount" => "1.0",
              "per_unit_total_amount" => "5.0",
              "flat_unit_amount" => "300.0"
            }
          ]
        },
        properties: {
          fixed_charges_from_datetime: "2025-09-01 00:00:00",
          fixed_charges_to_datetime: "2025-09-30 23:59:59"
        }
      )
    end

    # 4. Standard model - zero amount
    let(:zero_fixed_charge) do
      create(
        :fixed_charge,
        :pay_in_advance,
        plan:,
        add_on:
      )
    end
    let(:zero_fixed_charge_fee) do
      create(
        :fixed_charge_fee,
        invoice:,
        fixed_charge: zero_fixed_charge,
        subscription:,
        pay_in_advance: true,
        amount_cents: 0,
        amount_currency: "USD",
        units: 1,
        unit_amount_cents: 0,
        precise_unit_amount: 0.00,
        invoice_display_name: "Zero Pay in Advance Fixed Charge Fee",
        properties: {
          fixed_charges_from_datetime: "2025-09-01 00:00:00",
          fixed_charges_to_datetime: "2025-09-30 23:59:59"
        }
      )
    end

    # Pay in arrears fees
    # 5. Standard model - not prorated
    let(:arrears_fixed_charge) do
      create(
        :fixed_charge,
        plan:,
        add_on:
      )
    end
    let(:arrears_fixed_charge_fee) do
      create(
        :fixed_charge_fee,
        invoice:,
        fixed_charge: arrears_fixed_charge,
        subscription:,
        amount_cents: 8500,
        amount_currency: "USD",
        units: 1,
        unit_amount_cents: 8500,
        precise_unit_amount: 85.00,
        invoice_display_name: "Standard Pay in Arrears Fixed Charge Fee",
        properties: {
          fixed_charges_from_datetime: "2025-08-01 00:00:00",
          fixed_charges_to_datetime: "2025-08-31 23:59:59"
        }
      )
    end

    # 6. Graduated model - not prorated
    let(:arrears_graduated_fixed_charge) do
      create(
        :fixed_charge,
        :graduated,
        plan:,
        add_on:,
      )
    end
    let(:arrears_graduated_fixed_charge_fee) do
      create(
        :fixed_charge_fee,
        invoice:,
        fixed_charge: arrears_graduated_fixed_charge,
        subscription:,
        amount_cents: 55500,
        amount_currency: "USD",
        units: 15,
        unit_amount_cents: 3700,
        precise_unit_amount: 37.00,
        invoice_display_name: "Graduated Pay in Arrears Fixed Charge Fee",
        amount_details: {
          "graduated_ranges" => [
            {
              "from_value" => 0,
              "to_value" => 10,
              "units" => 10.0,
              "per_unit_amount" => "5.0",
              "per_unit_total_amount" => "50.0",
              "flat_unit_amount" => "200.0"
            },
            {
              "from_value" => 11,
              "to_value" => nil,
              "units" => 5.0,
              "per_unit_amount" => "1.0",
              "per_unit_total_amount" => "5.0",
              "flat_unit_amount" => "300.0"
            }
          ]
        },
        properties: {
          fixed_charges_from_datetime: "2025-08-01 00:00:00",
          fixed_charges_to_datetime: "2025-08-31 23:59:59"
        }
      )
    end

    # 7. Graduated model - prorated
    let(:arrears_graduated_prorated_fixed_charge) do
      create(
        :fixed_charge,
        :graduated,
        plan:,
        add_on:,
        prorated: true
      )
    end
    let(:arrears_graduated_prorated_fixed_charge_fee) do
      create(
        :fixed_charge_fee,
        invoice:,
        fixed_charge: arrears_graduated_prorated_fixed_charge,
        subscription:,
        amount_cents: 55500,
        amount_currency: "USD",
        units: 15,
        unit_amount_cents: 3700,
        precise_unit_amount: 37.00,
        invoice_display_name: "Graduated Pay in Arrears Prorated Fixed Charge Fee",
        amount_details: {
          "graduated_ranges" => [
            {
              "from_value" => 0,
              "to_value" => 10,
              "units" => 10.0,
              "per_unit_amount" => "5.0",
              "per_unit_total_amount" => "50.0",
              "flat_unit_amount" => "200.0"
            },
            {
              "from_value" => 11,
              "to_value" => nil,
              "units" => 5.0,
              "per_unit_amount" => "1.0",
              "per_unit_total_amount" => "5.0",
              "flat_unit_amount" => "300.0"
            }
          ]
        },
        properties: {
          fixed_charges_from_datetime: "2025-08-01 00:00:00",
          fixed_charges_to_datetime: "2025-08-31 23:59:59"
        }
      )
    end

    # 8. Volume model - not prorated
    let(:volume_fixed_charge) do
      create(
        :fixed_charge,
        :volume,
        plan:,
        add_on:
      )
    end
    let(:volume_fixed_charge_fee) do
      create(
        :fixed_charge_fee,
        invoice:,
        fixed_charge: volume_fixed_charge,
        subscription:,
        amount_cents: 15100,
        amount_currency: "USD",
        units: 75,
        unit_amount_cents: 201,
        precise_unit_amount: 2.01,
        invoice_display_name: "Volume Pay in Arrears Fixed Charge Fee",
        amount_details: {
          "per_unit_amount" => "2.0",
          "per_unit_total_amount" => "150.0",
          "flat_unit_amount" => "1.0"
        },
        properties: {
          fixed_charges_from_datetime: "2025-08-01 00:00:00",
          fixed_charges_to_datetime: "2025-08-31 23:59:59"
        }
      )
    end

    # 9. Volume model - prorated
    let(:volume_prorated_fixed_charge) do
      create(
        :fixed_charge,
        :volume,
        plan:,
        add_on:,
        prorated: true
      )
    end
    let(:volume_prorated_fixed_charge_fee) do
      create(
        :fixed_charge_fee,
        invoice:,
        fixed_charge: volume_prorated_fixed_charge,
        subscription:,
        amount_cents: 9200,
        amount_currency: "USD",
        units: 30,
        unit_amount_cents: 307,
        precise_unit_amount: 3.07,
        invoice_display_name: "Volume Pay in Arrears Prorated Fixed Charge Fee",
        amount_details: {
          "per_unit_amount" => "3.0",
          "per_unit_total_amount" => "90.0",
          "flat_unit_amount" => "2.0"
        },
        properties: {
          fixed_charges_from_datetime: "2025-08-01 00:00:00",
          fixed_charges_to_datetime: "2025-08-31 23:59:59"
        }
      )
    end

    # Commitment fee
    let(:minimum_commitment_fee) do
      create(
        :minimum_commitment_fee,
        invoice:,
        subscription:,
        amount_currency: "USD",
        invoice_display_name: "Minimum Commitment Fee"
      )
    end
    
    before do
      invoice_subscription
      subscription_fee
      minimum_commitment_fee
      # Pay in advance fees
      standard_fixed_charge_fee
      standard_prorated_fixed_charge_fee
      graduated_fixed_charge_fee
      zero_fixed_charge_fee
      # Pay in arrears fees
      arrears_fixed_charge_fee
      arrears_graduated_fixed_charge_fee
      arrears_graduated_prorated_fixed_charge_fee
      volume_fixed_charge_fee
      volume_prorated_fixed_charge_fee
    end

    it "renders correctly with all included fees types" do
      expect(rendered_template).to match_html_snapshot
    end
  end

  context "when invoice has different boundaries for fixed charges" do
    let(:organization) { create(:organization, :with_static_values) }
    let(:customer) { create(:customer, :with_static_values, organization:) }

    # Yearly plan with monthly billed fixed charges
    let(:plan) do
      create(
        :plan,
        organization:,
        interval: "yearly",
        pay_in_advance: false,
        invoice_display_name: "Annual Plan",
        bill_fixed_charges_monthly: true
      )
    end

    let(:subscription) do
      create(
        :subscription,
        customer:,
        plan:,
        status: "active"
      )
    end

    let(:invoice) do
      create(
        :invoice,
        customer:,
        number: "LAGO-202509-003",
        payment_due_date: Date.parse("2026-01-01"),
        issuing_date: Date.parse("2026-01-01"),
        invoice_type: :subscription,
        total_amount_cents: 5000,
        currency: "EUR",
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
        to_datetime: Time.zone.parse("2025-12-31 23:59:59"),
        charges_from_datetime: Time.zone.parse("2025-08-01 00:00:00"),
        charges_to_datetime: Time.zone.parse("2025-12-31 23:59:59"),
        # Fixed charges billed monthly have different boundaries
        fixed_charges_from_datetime: Time.zone.parse("2025-12-01 00:00:00"),
        fixed_charges_to_datetime: Time.zone.parse("2025-12-31 23:59:59"),
        timestamp: Time.zone.parse("2025-12-31 23:59:59")
      )
    end

    # Subscription fee for the yearly plan
    let(:subscription_fee) do
      create(
        :fee,
        invoice:,
        subscription:,
        fee_type: :subscription,
        amount_cents: 99900,
        amount_currency: "EUR",
        units: 1,
        unit_amount_cents: 99900,
        precise_unit_amount: 999.00,
        invoice_display_name: nil,
        properties: {
          from_datetime: "2025-08-01 00:00:00",
          to_datetime: "2025-12-31 23:59:59"
        }
      )
    end

    let(:add_on) { create(:add_on, organization:) }
    let(:monthly_fixed_charge) do
      create(
        :fixed_charge,
        plan:,
        add_on:
      )
    end
    let(:monthly_fixed_charge_fee) do
      create(
        :fixed_charge_fee,
        invoice:,
        subscription:,
        fixed_charge: monthly_fixed_charge,
        amount_cents: 10000,
        amount_currency: "EUR",
        units: 1,
        unit_amount_cents: 10000,
        precise_unit_amount: 100.00,
        invoice_display_name: "Monthly Fixed Charge",
        properties: {
          from_datetime: "2025-12-01 00:00:00",
          to_datetime: "2025-12-31 23:59:59"
        }
      )
    end

    before do
      invoice_subscription
      subscription_fee
      monthly_fixed_charge_fee
    end

    it "renders correctly with different boundaries" do
      expect(rendered_template).to match_html_snapshot
    end
  end

  context "when invoice_type is subscription and plan is paid in advance" do
    let(:organization) { create(:organization, :with_static_values) }
    let(:customer) { create(:customer, :with_static_values, organization:) }

    let(:plan) do
      create(
        :plan,
        organization:,
        interval: "monthly",
        pay_in_advance: true,
        invoice_display_name: "Premium Plan"
      )
    end

    let(:subscription) do
      create(:subscription, customer:, plan:, status: "active")
    end

    let(:invoice) do
      create(
        :invoice,
        customer:,
        number: "LAGO-202509-002",
        payment_due_date: Date.parse("2025-09-19"),
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
        invoice:,
        subscription:,
        from_datetime: Time.zone.parse("2025-09-01 00:00:00"),
        to_datetime: Time.zone.parse("2025-09-30 23:59:59"),
        charges_from_datetime: Time.zone.parse("2025-08-01 00:00:00"),
        charges_to_datetime: Time.zone.parse("2025-08-31 23:59:59"),
        fixed_charges_from_datetime: Time.zone.parse("2025-08-01 00:00:00"),
        fixed_charges_to_datetime: Time.zone.parse("2025-08-31 23:59:59"),
        timestamp: Time.zone.parse("2025-08-31 23:59:59")
      )
    end

    let(:subscription_fee) do
      create(
        :fee,
        invoice:,
        subscription:,
        pay_in_advance: true,
        fee_type: :subscription,
        amount_cents: 1500,
        amount_currency: "USD",
        units: 1,
        unit_amount_cents: 1500,
        precise_unit_amount: 15.00,
        invoice_display_name: "Pay in Advance Subscription Fee",
        properties: {
          from_datetime: "2025-09-01 00:00:00",
          to_datetime: "2025-09-30 23:59:59"
        }
      )
    end

    let(:add_on) { create(:add_on, organization: organization) }

    # Previous invoice subscription for the previous period
    let(:previous_invoice) do
      create(:invoice, customer:)
    end
    let(:previous_invoice_subscription) do
      create(
        :invoice_subscription,
        subscription:,
        invoice: previous_invoice,
        from_datetime: Time.zone.parse("2025-08-01 00:00:00"),
        to_datetime: Time.zone.parse("2025-08-31 23:59:59"),
        charges_from_datetime: Time.zone.parse("2025-07-01 00:00:00"),
        charges_to_datetime: Time.zone.parse("2025-07-31 23:59:59"),
        fixed_charges_from_datetime: Time.zone.parse("2025-07-01 00:00:00"),
        fixed_charges_to_datetime: Time.zone.parse("2025-07-31 23:59:59"),
        timestamp: Time.zone.parse("2025-07-31 23:59:59")
      )
    end
    let(:previous_subscription_fee) do
      create(
        :fee,
        invoice: previous_invoice,
        subscription:,
        pay_in_advance: true,
        fee_type: :subscription,
        amount_cents: 1500,
        amount_currency: "USD",
        units: 1,
        unit_amount_cents: 1500,
        precise_unit_amount: 15.00,
        properties: {
          from_datetime: "2025-08-01 00:00:00",
          to_datetime: "2025-08-31 23:59:59"
        }
      )
    end

    # Pay in advance fees
    # 1. Standard model - not prorated
    let(:standard_fixed_charge) do
      create(:fixed_charge, :pay_in_advance, plan:, add_on:)
    end
    let(:standard_fixed_charge_fee) do
      create(
        :fixed_charge_fee,
        invoice:,
        fixed_charge: standard_fixed_charge,
        subscription:,
        pay_in_advance: true,
        amount_cents: 5000,
        amount_currency: "USD",
        units: 2,
        unit_amount_cents: 2500,
        precise_unit_amount: 25.00,
        invoice_display_name: "Standard Pay in Advance Fixed Charge Fee",
        properties: {
          fixed_charges_from_datetime: "2025-09-01 00:00:00",
          fixed_charges_to_datetime: "2025-09-30 23:59:59"
        }
      )
    end

    # 2. Standard model - prorated
    let(:standard_prorated_fixed_charge) do
      create(
        :fixed_charge,
        :pay_in_advance,
        plan:,
        add_on:,
        prorated: true
      )
    end
    let(:standard_prorated_fixed_charge_fee) do
      create(
        :fixed_charge_fee,
        invoice:,
        fixed_charge: standard_prorated_fixed_charge,
        subscription:,
        pay_in_advance: true,
        amount_cents: 5000,
        amount_currency: "USD",
        units: 0.5,
        unit_amount_cents: 10000,
        precise_unit_amount: 100.00,
        invoice_display_name: "Standard Pay in Advance Prorated Fixed Charge Fee",
        properties: {
          fixed_charges_from_datetime: "2025-09-01 00:00:00",
          fixed_charges_to_datetime: "2025-09-30 23:59:59"
        }
      )
    end

    # 3. Graduated model - not prorated
    let(:graduated_fixed_charge) do
      create(
        :fixed_charge,
        :graduated,
        :pay_in_advance,
        plan:,
        add_on:
      )
    end
    let(:graduated_fixed_charge_fee) do
      create(
        :fixed_charge_fee,
        invoice:,
        fixed_charge: graduated_fixed_charge,
        subscription:,
        pay_in_advance: true,
        amount_cents: 55500,
        amount_currency: "USD",
        units: 15,
        unit_amount_cents: 3700,
        precise_unit_amount: 37.00,
        invoice_display_name: "Graduated Pay in Advance Fixed Charge Fee",
        amount_details: {
          "graduated_ranges" => [
            {
              "from_value" => 0,
              "to_value" => 10,
              "units" => 10.0,
              "per_unit_amount" => "5.0",
              "per_unit_total_amount" => "50.0",
              "flat_unit_amount" => "200.0"
            },
            {
              "from_value" => 11,
              "to_value" => nil,
              "units" => 5.0,
              "per_unit_amount" => "1.0",
              "per_unit_total_amount" => "5.0",
              "flat_unit_amount" => "300.0"
            }
          ]
        },
        properties: {
          fixed_charges_from_datetime: "2025-09-01 00:00:00",
          fixed_charges_to_datetime: "2025-09-30 23:59:59"
        }
      )
    end

    # 4. Standard model - zero amount
    let(:zero_fixed_charge) do
      create(
        :fixed_charge,
        :pay_in_advance,
        plan:,
        add_on:
      )
    end
    let(:zero_fixed_charge_fee) do
      create(
        :fixed_charge_fee,
        invoice:,
        fixed_charge: zero_fixed_charge,
        subscription:,
        pay_in_advance: true,
        amount_cents: 0,
        amount_currency: "USD",
        units: 1,
        unit_amount_cents: 0,
        precise_unit_amount: 0.00,
        invoice_display_name: "Zero Pay in Advance Fixed Charge Fee",
        properties: {
          fixed_charges_from_datetime: "2025-09-01 00:00:00",
          fixed_charges_to_datetime: "2025-09-30 23:59:59"
        }
      )
    end

    # Pay in arrears fees
    # 5. Standard model - not prorated
    let(:arrears_fixed_charge) do
      create(
        :fixed_charge,
        plan:,
        add_on:
      )
    end
    let(:arrears_fixed_charge_fee) do
      create(
        :fixed_charge_fee,
        invoice:,
        fixed_charge: arrears_fixed_charge,
        subscription:,
        amount_cents: 8500,
        amount_currency: "USD",
        units: 1,
        unit_amount_cents: 8500,
        precise_unit_amount: 85.00,
        invoice_display_name: "Standard Pay in Arrears Fixed Charge Fee",
        properties: {
          fixed_charges_from_datetime: "2025-08-01 00:00:00",
          fixed_charges_to_datetime: "2025-08-31 23:59:59"
        }
      )
    end

    # 6. Graduated model - not prorated
    let(:arrears_graduated_fixed_charge) do
      create(
        :fixed_charge,
        :graduated,
        plan:,
        add_on:,
      )
    end
    let(:arrears_graduated_fixed_charge_fee) do
      create(
        :fixed_charge_fee,
        invoice:,
        fixed_charge: arrears_graduated_fixed_charge,
        subscription:,
        amount_cents: 55500,
        amount_currency: "USD",
        units: 15,
        unit_amount_cents: 3700,
        precise_unit_amount: 37.00,
        invoice_display_name: "Graduated Pay in Arrears Fixed Charge Fee",
        amount_details: {
          "graduated_ranges" => [
            {
              "from_value" => 0,
              "to_value" => 10,
              "units" => 10.0,
              "per_unit_amount" => "5.0",
              "per_unit_total_amount" => "50.0",
              "flat_unit_amount" => "200.0"
            },
            {
              "from_value" => 11,
              "to_value" => nil,
              "units" => 5.0,
              "per_unit_amount" => "1.0",
              "per_unit_total_amount" => "5.0",
              "flat_unit_amount" => "300.0"
            }
          ]
        },
        properties: {
          fixed_charges_from_datetime: "2025-08-01 00:00:00",
          fixed_charges_to_datetime: "2025-08-31 23:59:59"
        }
      )
    end

    # 7. Graduated model - prorated
    let(:arrears_graduated_prorated_fixed_charge) do
      create(
        :fixed_charge,
        :graduated,
        plan:,
        add_on:,
        prorated: true
      )
    end
    let(:arrears_graduated_prorated_fixed_charge_fee) do
      create(
        :fixed_charge_fee,
        invoice:,
        fixed_charge: arrears_graduated_prorated_fixed_charge,
        subscription:,
        amount_cents: 55500,
        amount_currency: "USD",
        units: 15,
        unit_amount_cents: 3700,
        precise_unit_amount: 37.00,
        invoice_display_name: "Graduated Pay in Arrears Prorated Fixed Charge Fee",
        amount_details: {
          "graduated_ranges" => [
            {
              "from_value" => 0,
              "to_value" => 10,
              "units" => 10.0,
              "per_unit_amount" => "5.0",
              "per_unit_total_amount" => "50.0",
              "flat_unit_amount" => "200.0"
            },
            {
              "from_value" => 11,
              "to_value" => nil,
              "units" => 5.0,
              "per_unit_amount" => "1.0",
              "per_unit_total_amount" => "5.0",
              "flat_unit_amount" => "300.0"
            }
          ]
        },
        properties: {
          fixed_charges_from_datetime: "2025-08-01 00:00:00",
          fixed_charges_to_datetime: "2025-08-31 23:59:59"
        }
      )
    end

    # 8. Volume model - not prorated
    let(:volume_fixed_charge) do
      create(
        :fixed_charge,
        :volume,
        plan:,
        add_on:
      )
    end
    let(:volume_fixed_charge_fee) do
      create(
        :fixed_charge_fee,
        invoice:,
        fixed_charge: volume_fixed_charge,
        subscription:,
        amount_cents: 15100,
        amount_currency: "USD",
        units: 75,
        unit_amount_cents: 201,
        precise_unit_amount: 2.01,
        invoice_display_name: "Volume Pay in Arrears Fixed Charge Fee",
        amount_details: {
          "per_unit_amount" => "2.0",
          "per_unit_total_amount" => "150.0",
          "flat_unit_amount" => "1.0"
        },
        properties: {
          fixed_charges_from_datetime: "2025-08-01 00:00:00",
          fixed_charges_to_datetime: "2025-08-31 23:59:59"
        }
      )
    end

    # 9. Volume model - prorated
    let(:volume_prorated_fixed_charge) do
      create(
        :fixed_charge,
        :volume,
        plan:,
        add_on:,
        prorated: true
      )
    end
    let(:volume_prorated_fixed_charge_fee) do
      create(
        :fixed_charge_fee,
        invoice:,
        fixed_charge: volume_prorated_fixed_charge,
        subscription:,
        amount_cents: 9200,
        amount_currency: "USD",
        units: 30,
        unit_amount_cents: 307,
        precise_unit_amount: 3.07,
        invoice_display_name: "Volume Pay in Arrears Prorated Fixed Charge Fee",
        amount_details: {
          "per_unit_amount" => "3.0",
          "per_unit_total_amount" => "90.0",
          "flat_unit_amount" => "2.0"
        },
        properties: {
          fixed_charges_from_datetime: "2025-08-01 00:00:00",
          fixed_charges_to_datetime: "2025-08-31 23:59:59"
        }
      )
    end

    # Commitment fee
    let(:minimum_commitment_fee) do
      create(
        :minimum_commitment_fee,
        invoice:,
        subscription:,
        amount_currency: "USD",
        invoice_display_name: "Minimum Commitment Fee"
      )
    end
    
    before do
      # Previous invoice subscription for the previous period
      previous_invoice_subscription
      previous_subscription_fee

      invoice_subscription
      subscription_fee
      minimum_commitment_fee
      # Pay in advance fees
      standard_fixed_charge_fee
      standard_prorated_fixed_charge_fee
      graduated_fixed_charge_fee
      zero_fixed_charge_fee
      # Pay in arrears fees
      arrears_fixed_charge_fee
      arrears_graduated_fixed_charge_fee
      arrears_graduated_prorated_fixed_charge_fee
      volume_fixed_charge_fee
      volume_prorated_fixed_charge_fee
    end

    it "renders correctly with all included fees types" do
      expect(rendered_template).to match_html_snapshot
    end
  end
end
