# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::Taxes::CreditNotes::Payloads::Anrok do
  describe "#body" do
    subject(:payload) { described_class.new(integration:, customer:, integration_customer:, credit_note:).body }

    it_behaves_like "an integration payload", :anrok do
      def build_expected_payload(mapping_codes)
        [
          {
            "id" => "cn_#{credit_note.id}",
            "issuing_date" => credit_note.issuing_date,
            "currency" => credit_note.currency,
            "contact" => {
              "external_id" => integration_customer.external_customer_id,
              "name" => customer.name,
              "address_line_1" => customer.address_line1,
              "city" => customer.city,
              "zip" => customer.zipcode,
              "country" => customer.country,
              "taxable" => false,
              "tax_number" => nil
            },
            "fees" => match_array([
              {
                "item_id" => add_on.id,
                "amount_cents" => -190,
                "item_code" => mapping_codes.dig(:add_on, :external_id)
              },
              {
                "item_id" => billable_metric.id,
                "amount_cents" => -180,
                "item_code" => mapping_codes.dig(:billable_metric, :external_id)
              },
              {
                "item_id" => subscription.id,
                "amount_cents" => -170,
                "item_code" => mapping_codes.dig(:minimum_commitment, :external_id)
              },
              {
                "item_id" => subscription.id,
                "amount_cents" => -160,
                "item_code" => mapping_codes.dig(:subscription, :external_id)
              }
            ])
          }
        ]
      end
    end
  end
end
