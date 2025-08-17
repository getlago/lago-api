# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::Taxes::Invoices::Payloads::Anrok do
  let(:integration) { create(:anrok_integration, organization:) }
  let(:organization) { create(:organization) }
  let(:integration_customer) { create(:anrok_customer, customer:, integration:) }
  let(:customer) { create(:customer, organization:) }
  let(:payload) { described_class.new(integration:, customer:, invoice:, integration_customer:, fees:) }
  let(:add_on) { create(:add_on, organization:) }
  let(:add_on_two) { create(:add_on, organization:) }
  let(:current_time) { Time.current }
  let(:fees) { invoice.fees }
  let(:integration_collection_mapping1) do
    create(
      :netsuite_collection_mapping,
      integration:,
      mapping_type: :fallback_item,
      settings: {external_id: "1", external_account_code: "11", external_name: ""}
    )
  end
  let(:integration_mapping_add_on) do
    create(
      :netsuite_mapping,
      integration:,
      mappable_type: "AddOn",
      mappable_id: add_on.id,
      settings: {external_id: "m1", external_account_code: "m11", external_name: ""}
    )
  end
  let(:invoice) do
    create(
      :invoice,
      customer:,
      organization:
    )
  end
  let(:fee_add_on) do
    create(
      :fee,
      invoice:,
      add_on:,
      created_at: current_time - 3.seconds
    )
  end
  let(:fee_add_on_two) do
    create(
      :fee,
      invoice:,
      add_on: add_on_two,
      created_at: current_time - 2.seconds
    )
  end

  before do
    integration_customer
    integration_collection_mapping1
    integration_mapping_add_on
    fee_add_on
    fee_add_on_two
  end

  describe "#body" do
    subject(:call) { payload.body }

    let(:payload_body) do
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
            "country" => customer.shipping_country || customer.country,
            "taxable" => customer.tax_identification_number.present?,
            "tax_number" => customer.tax_identification_number
          },
          "fees" => [
            {
              "item_key" => fee_add_on.item_key,
              "item_id" => fee_add_on.id,
              "item_code" => "m1",
              "amount_cents" => 200
            },
            {
              "item_key" => fee_add_on_two.item_key,
              "item_id" => fee_add_on_two.id,
              "item_code" => "1",
              "amount_cents" => 200
            }
          ]
        }
      ]
    end

    it "returns the payload body" do
      expect(call).to eq payload_body
    end

    context "when invoice.issuing_date is too far in the future" do
      it "uses issuing date 30 days in the future at most" do
        invoice.issuing_date = 61.days.from_now.to_date
        expect(call.sole["issuing_date"]).to eq 30.days.from_now.to_date
      end
    end
  end
end
