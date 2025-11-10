# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::CreditNotes::Payloads::Netsuite do
  describe "#body" do
    subject(:payload) { described_class.new(integration_customer:, credit_note:).body }

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
          "options" => {"ignoreMandatoryFields" => false},
          "type" => "creditmemo"
        }
      end
    end
  end
end
