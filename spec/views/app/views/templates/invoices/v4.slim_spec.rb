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

  context "when invoice_type is subscription and plan is paid in arrears" do
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

    # 1. Standard model - not prorated
    let(:standard_addon) { create(:add_on, organization: organization, name: "Setup Fee", invoice_display_name: "Setup Fee") }
    let(:standard_fixed_charge) do
      create(
        :fixed_charge,
        organization: organization,
        plan: plan,
        add_on: standard_addon,
        charge_model: "standard",
        pay_in_advance: false,
        prorated: false,
        units: 2,
        invoice_display_name: "Setup Fee",
        properties: {amount: "25.00"}
      )
    end
    let(:standard_fee) do
      create(
        :fee,
        invoice: invoice,
        subscription: subscription,
        fixed_charge: standard_fixed_charge,
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

    # 2. Standard model - prorated
    let(:standard_prorated_addon) { create(:add_on, organization: organization, name: "Prorated Fee", invoice_display_name: "Prorated Fee") }
    let(:standard_prorated_fixed_charge) do
      create(
        :fixed_charge,
        organization: organization,
        plan: plan,
        add_on: standard_prorated_addon,
        charge_model: "standard",
        pay_in_advance: false,
        prorated: true,
        units: 1,
        invoice_display_name: "Prorated Setup Fee",
        properties: {amount: "100.00"}
      )
    end
    let(:standard_prorated_fee) do
      create(
        :fee,
        invoice: invoice,
        subscription: subscription,
        fixed_charge: standard_prorated_fixed_charge,
        fee_type: :fixed_charge,
        organization: organization,
        billing_entity: billing_entity,
        amount_cents: 5000,
        amount_currency: "USD",
        units: 0.5,
        unit_amount_cents: 10000,
        precise_unit_amount: 100.00,
        invoice_display_name: "Prorated Setup Fee",
        invoiceable: nil
      )
    end

    # 3. Graduated model - not prorated
    let(:graduated_addon) { create(:add_on, organization: organization, name: "Graduated Fee", invoice_display_name: "Graduated Fee") }
    let(:graduated_fixed_charge) do
      create(
        :fixed_charge,
        :graduated,
        organization: organization,
        plan: plan,
        add_on: graduated_addon,
        charge_model: "graduated",
        pay_in_advance: false,
        prorated: false,
        units: 1,
        invoice_display_name: "Graduated Fixed Charge",
        properties: {
          graduated_ranges: [
            {from_value: 0, to_value: 10, per_unit_amount: "5", flat_amount: "200"},
            {from_value: 11, to_value: nil, per_unit_amount: "1", flat_amount: "300"}
          ]
        }
      )
    end
    let(:graduated_fee) do
      create(
        :fee,
        invoice: invoice,
        subscription: subscription,
        fixed_charge: graduated_fixed_charge,
        fee_type: :fixed_charge,
        organization: organization,
        billing_entity: billing_entity,
        amount_cents: 55500,
        amount_currency: "USD",
        units: 15,
        unit_amount_cents: 3700,
        precise_unit_amount: 37.00,
        invoice_display_name: "Graduated Fixed Charge",
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
        invoiceable: nil
      )
    end

    # 4. Graduated model - prorated
    let(:graduated_prorated_addon) { create(:add_on, organization: organization, name: "Prorated Graduated Fee", invoice_display_name: "Prorated Graduated Fee") }
    let(:graduated_prorated_fixed_charge) do
      create(
        :fixed_charge,
        :graduated,
        organization: organization,
        plan: plan,
        add_on: graduated_prorated_addon,
        charge_model: "graduated",
        pay_in_advance: false,
        prorated: true,
        units: 1,
        invoice_display_name: "Prorated Graduated Fixed Charge",
        properties: {
          graduated_ranges: [
            {from_value: 0, to_value: 10, per_unit_amount: "3", flat_amount: "100"},
            {from_value: 11, to_value: nil, per_unit_amount: "0.5", flat_amount: "150"}
          ]
        }
      )
    end
    let(:graduated_prorated_fee) do
      create(
        :fee,
        invoice: invoice,
        subscription: subscription,
        fixed_charge: graduated_prorated_fixed_charge,
        fee_type: :fixed_charge,
        organization: organization,
        billing_entity: billing_entity,
        amount_cents: 28100,
        amount_currency: "USD",
        units: 12,
        unit_amount_cents: 2342,
        precise_unit_amount: 23.42,
        invoice_display_name: "Prorated Graduated Fixed Charge",
        amount_details: {
          "graduated_ranges" => [
            {
              "from_value" => 0,
              "to_value" => 10,
              "units" => 10.0,
              "per_unit_amount" => "3.0",
              "per_unit_total_amount" => "30.0",
              "flat_unit_amount" => "100.0"
            },
            {
              "from_value" => 11,
              "to_value" => nil,
              "units" => 2.0,
              "per_unit_amount" => "0.5",
              "per_unit_total_amount" => "1.0",
              "flat_unit_amount" => "150.0"
            }
          ]
        },
        invoiceable: nil
      )
    end

    # 5. Volume model - not prorated
    let(:volume_addon) { create(:add_on, organization: organization, name: "Volume Fee", invoice_display_name: "Volume Fee") }
    let(:volume_fixed_charge) do
      create(
        :fixed_charge,
        :volume,
        organization: organization,
        plan: plan,
        add_on: volume_addon,
        charge_model: "volume",
        pay_in_advance: false,
        prorated: false,
        units: 1,
        invoice_display_name: "Volume Fixed Charge",
        properties: {
          volume_ranges: [
            {from_value: 0, to_value: 100, per_unit_amount: "2", flat_amount: "1"},
            {from_value: 101, to_value: nil, per_unit_amount: "1", flat_amount: "0"}
          ]
        }
      )
    end
    let(:volume_fee) do
      create(
        :fee,
        invoice: invoice,
        subscription: subscription,
        fixed_charge: volume_fixed_charge,
        fee_type: :fixed_charge,
        organization: organization,
        billing_entity: billing_entity,
        amount_cents: 15100,
        amount_currency: "USD",
        units: 75,
        unit_amount_cents: 201,
        precise_unit_amount: 2.01,
        invoice_display_name: "Volume Fixed Charge",
        amount_details: {
          "per_unit_amount" => "2.0",
          "per_unit_total_amount" => "150.0",
          "flat_unit_amount" => "1.0"
        },
        invoiceable: nil
      )
    end

    # 6. Volume model - prorated
    let(:volume_prorated_addon) { create(:add_on, organization: organization, name: "Prorated Volume Fee", invoice_display_name: "Prorated Volume Fee") }
    let(:volume_prorated_fixed_charge) do
      create(
        :fixed_charge,
        :volume,
        organization: organization,
        plan: plan,
        add_on: volume_prorated_addon,
        charge_model: "volume",
        pay_in_advance: false,
        prorated: true,
        units: 1,
        invoice_display_name: "Prorated Volume Fixed Charge",
        properties: {
          volume_ranges: [
            {from_value: 0, to_value: 50, per_unit_amount: "3", flat_amount: "2"},
            {from_value: 51, to_value: nil, per_unit_amount: "1.5", flat_amount: "0"}
          ]
        }
      )
    end
    let(:volume_prorated_fee) do
      create(
        :fee,
        invoice: invoice,
        subscription: subscription,
        fixed_charge: volume_prorated_fixed_charge,
        fee_type: :fixed_charge,
        organization: organization,
        billing_entity: billing_entity,
        amount_cents: 9200,
        amount_currency: "USD",
        units: 30,
        unit_amount_cents: 307,
        precise_unit_amount: 3.07,
        invoice_display_name: "Prorated Volume Fixed Charge",
        amount_details: {
          "per_unit_amount" => "3.0",
          "per_unit_total_amount" => "90.0",
          "flat_unit_amount" => "2.0"
        },
        invoiceable: nil
      )
    end

    # 7. Standard model - zero amount
    let(:zero_addon) { create(:add_on, organization: organization, name: "Free Fee", invoice_display_name: "Free Fee") }
    let(:zero_fixed_charge) do
      create(
        :fixed_charge,
        organization: organization,
        plan: plan,
        add_on: zero_addon,
        charge_model: "standard",
        pay_in_advance: false,
        prorated: false,
        units: 1,
        invoice_display_name: "Free Setup Fee",
        properties: {amount: "0"}
      )
    end
    let(:zero_fee) do
      create(
        :fee,
        invoice: invoice,
        subscription: subscription,
        fixed_charge: zero_fixed_charge,
        fee_type: :fixed_charge,
        organization: organization,
        billing_entity: billing_entity,
        amount_cents: 0,
        amount_currency: "USD",
        units: 1,
        unit_amount_cents: 0,
        precise_unit_amount: 0.00,
        invoice_display_name: "Free Setup Fee",
        invoiceable: nil
      )
    end

    # 8. Fixed charge paid in advance (on plan paid in arrears)
    let(:advance_addon) { create(:add_on, organization: organization, name: "Advance Fee", invoice_display_name: "Advance Fee") }
    let(:advance_fixed_charge) do
      create(
        :fixed_charge,
        organization: organization,
        plan: plan,
        add_on: advance_addon,
        charge_model: "standard",
        pay_in_advance: true,
        prorated: false,
        units: 1,
        invoice_display_name: "Advance Fixed Charge",
        properties: {amount: "75.00"}
      )
    end
    let(:advance_fee) do
      create(
        :fee,
        invoice: invoice,
        subscription: subscription,
        fixed_charge: advance_fixed_charge,
        fee_type: :fixed_charge,
        organization: organization,
        billing_entity: billing_entity,
        amount_cents: 7500,
        amount_currency: "USD",
        units: 1,
        unit_amount_cents: 7500,
        precise_unit_amount: 75.00,
        invoice_display_name: "Advance Fixed Charge",
        invoiceable: nil
      )
    end

    before do
      invoice_subscription
      standard_fee
      standard_prorated_fee
      graduated_fee
      graduated_prorated_fee
      volume_fee
      volume_prorated_fee
      zero_fee
      advance_fee
    end

    it "renders correctly with all included fees types" do
      expect(rendered_template).to match_html_snapshot
    end
  end
end
