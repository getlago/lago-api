# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::Taxes::CreditNotes::Payloads::Avalara do
  subject(:payload) { described_class.new(integration:, customer:, integration_customer:, credit_note:).body }

  it_behaves_like "an integration payload", :avalara do
    def build_expected_payload(mapping_codes)
      [
        {
          "id" => "cn_#{credit_note.id}",
          "type" => "returnInvoice",
          "issuing_date" => credit_note.issuing_date,
          "currency" => credit_note.currency,
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
              "item_id" => add_on.id,
              "amount" => "-1.9",
              "unit" => 2.0,
              "item_code" => mapping_codes.dig(:add_on, :external_id)
            },
            {
              "item_id" => billable_metric.id,
              "amount" => "-1.8",
              "unit" => 3.0,
              "item_code" => mapping_codes.dig(:billable_metric, :external_id)
            },
            {
              "item_id" => subscription.id,
              "amount" => "-1.7",
              "unit" => 4.0,
              "item_code" => mapping_codes.dig(:minimum_commitment, :external_id)
            },
            {
              "item_id" => subscription.id,
              "amount" => "-1.6",
              "unit" => 5.0,
              "item_code" => mapping_codes.dig(:subscription, :external_id)
            }
          ])
        }
      ]
    end
  end
end
