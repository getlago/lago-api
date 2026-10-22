# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::CreditNotes::Payloads::Anrok do
  describe "#body" do
    subject(:payload) { described_class.new(integration_customer:, credit_note:).body }

    context "when credit note has a contract product fee without a subscription" do
      let(:organization) { create(:organization) }
      let(:billing_entity) { create(:billing_entity, organization:) }
      let(:source_billing_entity) { create(:billing_entity, organization:) }
      let(:customer) { create(:customer, organization:, billing_entity:) }
      let(:integration) { create(:anrok_integration, organization:) }
      let(:integration_customer) { create(:anrok_customer, integration:, customer:) }
      let(:product) { create(:product, organization:, name: "Contract Product") }
      let(:contract) { create(:contract, organization:, customer:) }
      let(:rate_card) { create(:rate_card, organization:, product:) }
      let(:rate_card_rate) { create(:rate_card_rate, organization:, rate_card:) }
      let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }
      let(:invoice) { create(:invoice, customer:, organization:, billing_entity: source_billing_entity) }
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
          :anrok_mapping,
          integration:,
          organization:,
          billing_entity:,
          mappable: product,
          settings: {external_id: "customer-product-item", external_account_code: "customer-product-account"}
        )
        create(
          :anrok_mapping,
          integration:,
          organization:,
          billing_entity: source_billing_entity,
          mappable: product,
          settings: {external_id: "invoice-product-item", external_account_code: "invoice-product-account"}
        )
        integration_customer
        credit_note_item
        credit_note.reload
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
                  "external_id" => "invoice-product-item",
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

    it_behaves_like "an integration payload", :anrok do
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
               "external_id" => mapping_codes.dig(:add_on, :external_id),
               "precise_unit_amount" => 1.9,
               "taxes_amount_cents" => 0.0,
               "units" => 1
             },
             {
               "account_code" => mapping_codes.dig(:fixed_charge, :external_account_code),
               "description" => "Fixed Charge Fee",
               "external_id" => mapping_codes.dig(:fixed_charge, :external_id),
               "precise_unit_amount" => 1.4,
               "taxes_amount_cents" => 0.0,
               "units" => 1
             },
             {
               "account_code" => mapping_codes.dig(:billable_metric, :external_account_code),
               "description" => "Standard Charge Fee",
               "external_id" => mapping_codes.dig(:billable_metric, :external_id),
               "precise_unit_amount" => 1.8,
               "taxes_amount_cents" => 0.0,
               "units" => 1
             },
             {
               "account_code" => mapping_codes.dig(:minimum_commitment, :external_account_code),
               "description" => "Minimum Commitment Fee",
               "external_id" => mapping_codes.dig(:minimum_commitment, :external_id),
               "precise_unit_amount" => 1.7,
               "taxes_amount_cents" => 0.0,
               "units" => 1
             },
             {
               "account_code" => mapping_codes.dig(:subscription, :external_account_code),
               "description" => "Subscription",
               "external_id" => mapping_codes.dig(:subscription, :external_id),
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
    end
  end
end
