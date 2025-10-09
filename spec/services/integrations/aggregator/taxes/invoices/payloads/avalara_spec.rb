# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::Taxes::Invoices::Payloads::Avalara do
  describe "#body" do
    subject(:payload) { described_class.new(integration:, customer:, invoice:, integration_customer:, fees:).body }

    it_behaves_like "an integration payload", :avalara do
      def build_expected_payload(mapping_codes, negative_amount: false)
        [
          {
            "issuing_date" => invoice.issuing_date,
            "currency" => invoice.currency,
            "contact" => {
              "external_id" => integration_customer&.external_customer_id || customer.external_id,
              "name" => customer.name,
              "address_line_1" => customer.shipping_address_line1 || customer.address_line1,
              "city" => customer.shipping_city || customer.city,
              "zip" => customer.shipping_zipcode || customer.zipcode,
              "region" => customer.shipping_state || customer.state,
              "country" => customer.shipping_country || customer.country,
              "taxable" => customer.tax_identification_number.present?,
              "tax_number" => customer.tax_identification_number
            },
            "billing_entity" => {
              "address_line_1" => customer.billing_entity.address_line1,
              "city" => customer.billing_entity.city,
              "zip" => customer.billing_entity.zipcode,
              "region" => customer.billing_entity.state,
              "country" => customer.billing_entity.country
            },
            "fees" => match_array([
              {
                "item_key" => add_on_fee.item_key,
                "item_id" => add_on_fee.id,
                "amount" => negative_amount ? "-2.0" : "2.0",
                "unit" => 2.0,
                "item_code" => mapping_codes.dig(:add_on, :external_id)
              },
              {
                "item_key" => billable_metric_fee.item_key,
                "item_id" => billable_metric_fee.id,
                "amount" => negative_amount ? "-3.0" : "3.0",
                "unit" => 3.0,
                "item_code" => mapping_codes.dig(:billable_metric, :external_id)
              },
              {
                "item_key" => minimum_commitment_fee.item_key,
                "item_id" => minimum_commitment_fee.id,
                "amount" => negative_amount ? "-4.0" : "4.0",
                "unit" => 4.0,
                "item_code" => mapping_codes.dig(:minimum_commitment, :external_id)
              },
              {
                "item_key" => subscription_fee.item_key,
                "item_id" => subscription_fee.id,
                "amount" => negative_amount ? "-5.0" : "5.0",
                "unit" => 5.0,
                "item_code" => mapping_codes.dig(:subscription, :external_id)
              }
            ])
          }
        ]
      end

      context "when invoice is voided" do
        before { invoice.voided! }

        it "returns the payload body" do
          expect(payload).to match_array build_expected_payload(default_mapping_codes, negative_amount: true)
        end
      end
    end
  end
end
