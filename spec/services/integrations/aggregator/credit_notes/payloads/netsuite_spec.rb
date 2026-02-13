# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::CreditNotes::Payloads::Netsuite do
  describe "#body" do
    subject(:payload) { described_class.new(integration_customer:, credit_note:).body }

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
          "options" => {"ignoreMandatoryFields" => false},
          "type" => "creditmemo"
        }
      end
    end
  end
end
