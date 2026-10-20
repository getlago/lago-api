# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::CreditNotes::Payloads::Netsuite do
  describe "#body" do
    subject(:payload) { described_class.new(integration_customer:, credit_note:).body }

    context "when credit note has a contract product fee without a subscription" do
      let(:organization) { create(:organization) }
      let(:billing_entity) { create(:billing_entity, organization:) }
      let(:customer) { create(:customer, organization:, billing_entity:) }
      let(:integration) { create(:netsuite_integration, organization:) }
      let(:integration_customer) { create(:netsuite_customer, integration:, customer:) }
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
          :netsuite_mapping,
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
        expect(payload.dig("lines", 0, "lineItems")).to eq(
          [
            {
              "item" => "contract-product-item",
              "account" => "contract-product-account",
              "quantity" => 1,
              "rate" => 20.0,
              "taxdetailsreference" => credit_note_item.id,
              "description" => "Contract Product"
            }
          ]
        )
      end

      context "when the customer's current billing entity differs from the invoice billing entity" do
        let(:source_billing_entity) { create(:billing_entity, organization:) }
        let(:invoice) { create(:invoice, customer:, organization:, billing_entity: source_billing_entity) }

        before do
          create(
            :netsuite_mapping,
            integration:,
            billing_entity: source_billing_entity,
            mappable: product,
            settings: {external_id: "invoice-product-item", external_account_code: "invoice-product-account"}
          )
        end

        it "uses the source invoice billing entity's product mapping" do
          expect(payload.dig("lines", 0, "lineItems")).to eq(
            [
              {
                "item" => "invoice-product-item",
                "account" => "invoice-product-account",
                "quantity" => 1,
                "rate" => 20.0,
                "taxdetailsreference" => credit_note_item.id,
                "description" => "Contract Product"
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
          create(:add_on_fee, invoice:, add_on:, amount_cents: 1_000, taxes_rate: 0, taxes_amount_cents: 0)
        end
        let(:add_on_credit_note_item) do
          create(:credit_note_item, credit_note:, fee: add_on_fee, amount_cents: 1_000)
        end
        let(:booked_tax) { create(:tax, organization:, code: "contract-product-vat", rate: 20) }

        before do
          create(
            :netsuite_mapping,
            integration:,
            billing_entity:,
            mappable: add_on,
            settings: {external_id: "untaxed-addon-item", external_account_code: "untaxed-addon-account"}
          )
          create(
            :netsuite_collection_mapping,
            integration:,
            mapping_type: :tax,
            settings: {external_id: "tax-item", external_account_code: "tax-account", external_name: "Tax", tax_nexus: "nexus", tax_type: "sale", tax_code: "tax-code"}
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
          expect(payload.dig("taxdetails", 0, "lineItems")).to eq(
            [
              {
                "taxdetailsreference" => credit_note_item.id,
                "taxamount" => 1.0,
                "taxbasis" => 1,
                "taxrate" => 20,
                "taxtype" => "sale",
                "taxcode" => "tax-code"
              },
              {
                "taxdetailsreference" => add_on_credit_note_item.id,
                "taxamount" => 1.0,
                "taxbasis" => 1,
                "taxrate" => 0,
                "taxtype" => "sale",
                "taxcode" => "tax-code"
              }
            ]
          )
        end
      end
    end

    context "when credit note has a fixed_charge fee" do
      let(:organization) { create(:organization) }
      let(:customer) { create(:customer, organization:) }
      let(:integration) { create(:netsuite_integration, organization:) }
      let(:integration_customer) { create(:netsuite_customer, integration:, customer:) }

      let(:add_on) { create(:add_on, organization:) }
      let(:plan) { create(:plan, organization:) }
      let(:fixed_charge) { create(:fixed_charge, organization:, plan:, add_on:) }

      let(:invoice) { create(:invoice, customer:, organization:) }
      let(:fixed_charge_fee) { create(:fixed_charge_fee, invoice:, fixed_charge:, amount_cents: 5000) }
      let(:credit_note) { create(:credit_note, customer:, invoice:) }
      let(:fixed_charge_credit_note_item) { create(:credit_note_item, credit_note:, fee: fixed_charge_fee, amount_cents: 2500) }

      let(:integration_mapping_add_on) do
        create(
          :netsuite_mapping,
          integration:,
          mappable_type: "AddOn",
          mappable_id: add_on.id,
          settings: {external_id: "fc-ext-id", external_account_code: "fc-account", external_name: ""}
        )
      end

      before do
        integration_customer
        integration_mapping_add_on
        fixed_charge_credit_note_item
        credit_note.reload
      end

      it "includes the fixed_charge fee using the add_on mapping" do
        line_items = payload["lines"].first["lineItems"]
        fixed_charge_line = line_items.find { |item| item["taxdetailsreference"] == fixed_charge_credit_note_item.id }

        expect(fixed_charge_line).to be_present
        expect(fixed_charge_line["item"]).to eq("fc-ext-id")
        expect(fixed_charge_line["account"]).to eq("fc-account")
      end
    end

    it_behaves_like "an integration payload", :netsuite do
      def build_expected_payload(mapping_codes)
        {
          "columns" => {
            "custbody_ava_disable_tax_calculation" => true,
            "custbody_lago_id" => credit_note.id,
            "entity" => integration_customer.external_customer_id,
            "otherrefnum" => credit_note.number,
            "taxdetailsoverride" => true,
            "taxregoverride" => true,
            "tranId" => credit_note.id,
            "tranid" => credit_note.number
          },
          "isDynamic" => true,
          "lines" => [
            {
              "lineItems" => [
                {
                  "account" => mapping_codes.dig(:add_on, :external_account_code),
                  "description" => "Add-on",
                  "item" => mapping_codes.dig(:add_on, :external_id),
                  "quantity" => 1,
                  "rate" => 1.9,
                  "taxdetailsreference" => add_on_credit_note_item.id
                },
                {
                  "account" => mapping_codes.dig(:fixed_charge, :external_account_code),
                  "description" => "Fixed Charge Add-on",
                  "item" => mapping_codes.dig(:fixed_charge, :external_id),
                  "quantity" => 1,
                  "rate" => 1.4,
                  "taxdetailsreference" => fixed_charge_credit_note_item.id
                },
                {
                  "account" => mapping_codes.dig(:billable_metric, :external_account_code),
                  "description" => "Billable Metric",
                  "item" => mapping_codes.dig(:billable_metric, :external_id),
                  "quantity" => 1,
                  "rate" => 1.8,
                  "taxdetailsreference" => billable_metric_credit_note_item.id
                },
                {
                  "account" => mapping_codes.dig(:minimum_commitment, :external_account_code),
                  "description" => "Plan",
                  "item" => mapping_codes.dig(:minimum_commitment, :external_id),
                  "quantity" => 1,
                  "rate" => 1.7,
                  "taxdetailsreference" => minimum_commitment_credit_note_item.id
                },
                {"account" => mapping_codes.dig(:subscription, :external_account_code),
                 "description" => "Plan",
                 "item" => mapping_codes.dig(:subscription, :external_id),
                 "quantity" => 1,
                 "rate" => 1.6,
                 "taxdetailsreference" => subscription_credit_note_item.id}
              ],
              "sublistId" => "item"
            }
          ],
          "options" => {
            "ignoreMandatoryFields" => false,
            "fullCreditNotePayload" => {
              "credit_note_payload" => hash_including(
                lago_id: credit_note.id,
                billing_entity_code: invoice.billing_entity.code,
                sequential_id: credit_note.sequential_id,
                number: credit_note.number,
                lago_invoice_id: invoice.id,
                invoice_number: invoice.number,
                issuing_date: credit_note.issuing_date&.iso8601,
                credit_status: credit_note.credit_status,
                refund_status: credit_note.refund_status,
                reason: credit_note.reason,
                description: credit_note.description,
                currency: credit_note.currency,
                total_amount_cents: credit_note.total_amount_cents,
                precise_total_amount_cents: credit_note.precise_total&.to_s,
                taxes_amount_cents: credit_note.taxes_amount_cents,
                precise_taxes_amount_cents: credit_note.precise_taxes_amount_cents&.to_s,
                sub_total_excluding_taxes_amount_cents: credit_note.sub_total_excluding_taxes_amount_cents,
                balance_amount_cents: credit_note.balance_amount_cents,
                credit_amount_cents: credit_note.credit_amount_cents,
                refund_amount_cents: credit_note.refund_amount_cents,
                offset_amount_cents: credit_note.offset_amount_cents,
                coupons_adjustment_amount_cents: credit_note.coupons_adjustment_amount_cents,
                taxes_rate: credit_note.taxes_rate,
                created_at: credit_note.created_at.iso8601,
                updated_at: credit_note.updated_at.iso8601,
                customer: hash_including(
                  lago_id: customer.id,
                  external_id: customer.external_id,
                  name: customer.name,
                  integration_customers: anything
                ),
                items: credit_note.items.map do |item|
                  hash_including(
                    lago_id: item.id
                  )
                end,
                applied_taxes: anything
              )
            }
          },
          "type" => "creditmemo"
        }
      end
    end
  end
end
