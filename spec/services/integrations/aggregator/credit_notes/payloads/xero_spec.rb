# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::CreditNotes::Payloads::Xero do
  describe "#body" do
    subject(:payload) { described_class.new(integration_customer:, credit_note:).body }

    context "when credit note has a contract product fee without a subscription" do
      let(:organization) { create(:organization) }
      let(:billing_entity) { create(:billing_entity, organization:) }
      let(:customer) { create(:customer, organization:, billing_entity:) }
      let(:integration) { create(:xero_integration, organization:) }
      let(:integration_customer) { create(:xero_customer, integration:, customer:) }
      let(:product) { create(:product, organization:, name: "Contract Product") }
      let(:contract) { create(:contract, organization:, customer:) }
      let(:rate_card) { create(:rate_card, organization:, product:) }
      let(:rate_card_rate) { create(:rate_card_rate, organization:, rate_card:) }
      let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }
      let(:invoice) { create(:invoice, customer:, organization:, billing_entity:) }
      let(:product_fee) do
        create(
          :product_fee,
          invoice:,
          organization:,
          subscription: nil,
          contract:,
          contract_rate_card:,
          rate_card_rate:,
          invoiceable: product,
          invoice_display_name: "Contract product fee",
          amount_cents: 2_000,
          precise_unit_amount: 2_000
        )
      end
      let(:credit_note) { create(:credit_note, customer:, invoice:, taxes_amount_cents: 0, taxes_rate: 0) }
      let(:credit_note_item) { create(:credit_note_item, credit_note:, fee: product_fee, amount_cents: 2_000) }

      before do
        create(
          :xero_mapping,
          integration:,
          billing_entity:,
          mappable: product,
          settings: {external_id: "contract-product-item", external_account_code: "contract-product-account"}
        )
        integration_customer
        credit_note_item
        credit_note.reload
      end

      it "serializes the fee using the product mapping for the billing entity" do
        expect(payload).to eq(
          [
            {
              "currency" => "EUR",
              "external_contact_id" => integration_customer.external_customer_id,
              "fees" => [
                {
                  "account_code" => "contract-product-account",
                  "description" => "Contract product fee",
                  "item_code" => "contract-product-item",
                  "precise_unit_amount" => 20.0,
                  "taxes_amount_cents" => 0.0,
                  "units" => 1
                }
              ],
              "issuing_date" => credit_note.issuing_date.to_time.utc.iso8601,
              "number" => credit_note.number,
              "status" => "AUTHORISED",
              "type" => "ACCRECCREDIT"
            }
          ]
        )
      end

      context "when the customer's current billing entity differs from the invoice billing entity" do
        let(:source_billing_entity) { create(:billing_entity, organization:) }
        let(:invoice) { create(:invoice, customer:, organization:, billing_entity: source_billing_entity) }

        before do
          create(
            :xero_mapping,
            integration:,
            billing_entity: source_billing_entity,
            mappable: product,
            settings: {external_id: "invoice-product-item", external_account_code: "invoice-product-account"}
          )
        end

        it "uses the source invoice billing entity's product mapping" do
          expect(payload).to eq(
            [
              {
                "currency" => "EUR",
                "external_contact_id" => integration_customer.external_customer_id,
                "fees" => [
                  {
                    "account_code" => "invoice-product-account",
                    "description" => "Contract product fee",
                    "item_code" => "invoice-product-item",
                    "precise_unit_amount" => 20.0,
                    "taxes_amount_cents" => 0.0,
                    "units" => 1
                  }
                ],
                "issuing_date" => credit_note.issuing_date.to_time.utc.iso8601,
                "number" => credit_note.number,
                "status" => "AUTHORISED",
                "type" => "ACCRECCREDIT"
              }
            ]
          )
        end
      end

      context "when the credit note has fees with different tax rates" do
        let(:product_fee) do
          create(
            :product_fee,
            invoice:,
            organization:,
            subscription: nil,
            contract:,
            contract_rate_card:,
            rate_card_rate:,
            invoiceable: product,
            invoice_display_name: "Contract product fee",
            amount_cents: 1_000,
            precise_unit_amount: 1_000,
            taxes_rate: 20,
            taxes_amount_cents: 200
          )
        end
        let(:credit_note) do
          create(:credit_note, customer:, invoice:, taxes_amount_cents: 200, taxes_rate: 10)
        end
        let(:credit_note_item) do
          create(:credit_note_item, credit_note:, fee: product_fee, amount_cents: 1_000)
        end
        let(:add_on) { create(:add_on, organization:, name: "Untaxed Add-on") }
        let(:add_on_fee) do
          create(
            :add_on_fee,
            invoice:,
            add_on:,
            invoice_display_name: "Untaxed Add-on",
            amount_cents: 1_000,
            taxes_rate: 0,
            taxes_amount_cents: 0
          )
        end
        let(:add_on_credit_note_item) do
          create(:credit_note_item, credit_note:, fee: add_on_fee, amount_cents: 1_000)
        end
        let(:booked_tax) { create(:tax, organization:, code: "contract-product-vat", rate: 20) }

        before do
          create(
            :xero_mapping,
            integration:,
            billing_entity:,
            mappable: add_on,
            settings: {external_id: "untaxed-addon-item", external_account_code: "untaxed-addon-account"}
          )
          create(:fee_applied_tax, fee: product_fee, tax: booked_tax, tax_code: booked_tax.code, tax_rate: 20, amount_cents: 200)
          create(
            :invoice_applied_tax,
            invoice:,
            tax: booked_tax,
            tax_code: booked_tax.code,
            tax_rate: 20,
            amount_cents: 200,
            fees_amount_cents: 1_000,
            taxable_base_amount_cents: 1_000
          )
          create(
            :credit_note_applied_tax,
            credit_note:,
            tax: booked_tax,
            tax_code: booked_tax.code,
            tax_rate: 20,
            amount_cents: 200,
            base_amount_cents: 1_000
          )
          add_on_credit_note_item
          credit_note.reload
        end

        it "blends the credit note tax rate across fees and preserves the tax total" do
          expect(credit_note.taxes_amount_cents).to eq(200)
          expect(payload).to eq(
            [
              {
                "currency" => "EUR",
                "external_contact_id" => integration_customer.external_customer_id,
                "fees" => [
                  {
                    "account_code" => "contract-product-account",
                    "description" => "Contract product fee",
                    "item_code" => "contract-product-item",
                    "precise_unit_amount" => 10.0,
                    "taxes_amount_cents" => 100.0,
                    "units" => 1
                  },
                  {
                    "account_code" => "untaxed-addon-account",
                    "description" => "Untaxed Add-on",
                    "item_code" => "untaxed-addon-item",
                    "precise_unit_amount" => 10.0,
                    "taxes_amount_cents" => 100.0,
                    "units" => 1
                  }
                ],
                "issuing_date" => credit_note.issuing_date.to_time.utc.iso8601,
                "number" => credit_note.number,
                "status" => "AUTHORISED",
                "type" => "ACCRECCREDIT"
              }
            ]
          )
        end
      end
    end

    context "when a provider booked less tax than the product fee's nominal rate" do
      let(:organization) { create(:organization) }
      let(:billing_entity) { create(:billing_entity, organization:) }
      let(:customer) { create(:customer, organization:, billing_entity:) }
      let(:integration) { create(:xero_integration, organization:) }
      let(:integration_customer) { create(:xero_customer, integration:, customer:) }
      let(:product) { create(:product, organization:, name: "Provider-taxed Product") }
      let(:contract) { create(:contract, organization:, customer:) }
      let(:rate_card) { create(:rate_card, organization:, product:) }
      let(:rate_card_rate) { create(:rate_card_rate, organization:, rate_card:) }
      let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }
      let(:invoice) do
        create(
          :invoice,
          customer:,
          organization:,
          billing_entity:,
          fees_amount_cents: 2_000,
          taxes_amount_cents: 75,
          total_amount_cents: 2_075,
          taxes_rate: 3.75
        )
      end
      let(:product_fee) do
        create(
          :product_fee,
          invoice:,
          organization:,
          subscription: nil,
          contract:,
          contract_rate_card:,
          rate_card_rate:,
          invoiceable: product,
          invoice_display_name: "Provider-taxed Product",
          amount_cents: 1_000,
          precise_unit_amount: 1_000,
          taxes_rate: 20,
          taxes_amount_cents: 75
        )
      end
      let(:add_on) { create(:add_on, organization:, name: "Exempt Add-on") }
      let(:add_on_fee) do
        create(
          :add_on_fee,
          invoice:,
          add_on:,
          invoice_display_name: "Exempt Add-on",
          amount_cents: 1_000,
          taxes_rate: 0,
          taxes_amount_cents: 0
        )
      end
      let(:credit_note) do
        create(:credit_note, customer:, invoice:, taxes_amount_cents: 75, taxes_rate: 3.75)
      end
      let(:product_credit_note_item) do
        create(:credit_note_item, credit_note:, fee: product_fee, amount_cents: 1_000)
      end
      let(:add_on_credit_note_item) do
        create(:credit_note_item, credit_note:, fee: add_on_fee, amount_cents: 1_000)
      end
      let(:fee_tax) do
        create(
          :fee_applied_tax,
          fee: product_fee,
          tax: nil,
          tax_code: "provider-sales-tax",
          tax_rate: 20,
          amount_cents: 75
        )
      end

      before do
        create(
          :invoice_applied_tax,
          invoice:,
          tax: nil,
          tax_code: "provider-sales-tax",
          tax_rate: 20,
          amount_cents: 75,
          fees_amount_cents: 375,
          taxable_base_amount_cents: 375
        )
        create(
          :credit_note_applied_tax,
          credit_note:,
          tax: nil,
          tax_code: "provider-sales-tax",
          tax_rate: 20,
          amount_cents: 75,
          base_amount_cents: 375
        )
        create(
          :xero_mapping,
          integration:,
          billing_entity:,
          mappable: product,
          settings: {external_id: "provider-taxed-product", external_account_code: "provider-product-account"}
        )
        create(
          :xero_mapping,
          integration:,
          billing_entity:,
          mappable: add_on,
          settings: {external_id: "exempt-addon", external_account_code: "exempt-addon-account"}
        )
        integration_customer
        product_credit_note_item
        add_on_credit_note_item
        fee_tax
        credit_note.reload
      end

      it "blends the credit note tax rate across fees for provider-booked tax" do
        expect(invoice.provider_taxes?).to be(true)
        expect(invoice.booked_tax_by_fee_tax.fetch(fee_tax)).to eq(75)
        expect(credit_note.applied_taxes.sum(&:amount_cents)).to eq(75)
        expect(payload).to eq(
          [
            {
              "currency" => "EUR",
              "external_contact_id" => integration_customer.external_customer_id,
              "fees" => [
                {
                  "account_code" => "provider-product-account",
                  "description" => "Provider-taxed Product",
                  "item_code" => "provider-taxed-product",
                  "precise_unit_amount" => 10.0,
                  "taxes_amount_cents" => 37.5,
                  "units" => 1
                },
                {
                  "account_code" => "exempt-addon-account",
                  "description" => "Exempt Add-on",
                  "item_code" => "exempt-addon",
                  "precise_unit_amount" => 10.0,
                  "taxes_amount_cents" => 37.5,
                  "units" => 1
                }
              ],
              "issuing_date" => credit_note.issuing_date.to_time.utc.iso8601,
              "number" => credit_note.number,
              "status" => "AUTHORISED",
              "type" => "ACCRECCREDIT"
            }
          ]
        )
      end
    end

    it_behaves_like "an integration payload", :xero do
      def build_expected_payload(mapping_codes)
        [
          {
            "currency" => "EUR",
            "external_contact_id" => integration_customer.external_customer_id,
            "fees" =>
           [
             {
               "account_code" => mapping_codes.dig(:add_on, :external_account_code),
               "description" => "Add-on Fee",
               "item_code" => mapping_codes.dig(:add_on, :external_id),
               "precise_unit_amount" => 1.9,
               "taxes_amount_cents" => 0.0,
               "units" => 1
             },
             {
               "account_code" => mapping_codes.dig(:fixed_charge, :external_account_code),
               "description" => "Fixed Charge Fee",
               "item_code" => mapping_codes.dig(:fixed_charge, :external_id),
               "precise_unit_amount" => 1.4,
               "taxes_amount_cents" => 0.0,
               "units" => 1
             },
             {
               "account_code" => mapping_codes.dig(:billable_metric, :external_account_code),
               "description" => "Standard Charge Fee",
               "item_code" => mapping_codes.dig(:billable_metric, :external_id),
               "precise_unit_amount" => 1.8,
               "taxes_amount_cents" => 0.0,
               "units" => 1
             },
             {
               "account_code" => mapping_codes.dig(:minimum_commitment, :external_account_code),
               "description" => "Minimum Commitment Fee",
               "item_code" => mapping_codes.dig(:minimum_commitment, :external_id),
               "precise_unit_amount" => 1.7,
               "taxes_amount_cents" => 0.0,
               "units" => 1
             },
             {
               "account_code" => mapping_codes.dig(:subscription, :external_account_code),
               "description" => "Subscription",
               "item_code" => mapping_codes.dig(:subscription, :external_id),
               "precise_unit_amount" => 1.6,
               "taxes_amount_cents" => 0.0,
               "units" => 1
             }
           ],
            "issuing_date" => "2024-07-08T00:00:00Z",
            "number" => credit_note.number,
            "status" => "AUTHORISED",
            "type" => "ACCRECCREDIT"
          }
        ]
      end

      context "when there are coupons" do
        let(:credit_note) { create(:credit_note, customer:, invoice:, issuing_date: DateTime.new(2024, 7, 8), coupons_adjustment_amount_cents: 50) }

        it "returns coupons with item_code instead of external_id" do
          expect(payload.first["fees"]).to include(
            {
              "account_code" => default_mapping_codes.dig(:coupon, :external_account_code),
              "description" => "Coupons",
              "item_code" => default_mapping_codes.dig(:coupon, :external_id),
              "precise_unit_amount" => -0.5,
              "taxes_amount_cents" => 0,
              "units" => 1
            }
          )
        end
      end
    end
  end
end
