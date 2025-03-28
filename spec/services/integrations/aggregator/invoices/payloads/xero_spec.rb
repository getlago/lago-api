# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::Invoices::Payloads::Xero do
  describe "#body" do
    subject(:body_call) { payload.body }

    let(:payload) { described_class.new(integration_customer:, invoice:) }
    let(:integration_customer) { FactoryBot.create(:xero_customer, integration:, customer:) }
    let(:integration) { create(:netsuite_integration, organization:) }
    let(:customer) { create(:customer, organization:) }
    let(:organization) { create(:organization) }
    let(:add_on) { create(:add_on, organization:) }
    let(:billable_metric) { create(:billable_metric, organization:) }
    let(:charge) { create(:standard_charge, billable_metric:) }
    let(:current_time) { Time.current }

    let(:integration_collection_mapping1) do
      create(
        :netsuite_collection_mapping,
        integration:,
        mapping_type: :fallback_item,
        settings: {external_id: "1", external_account_code: "11", external_name: ""}
      )
    end

    let(:integration_collection_mapping2) do
      create(
        :netsuite_collection_mapping,
        integration:,
        mapping_type: :coupon,
        settings: {external_id: "2", external_account_code: "22", external_name: ""}
      )
    end

    let(:integration_collection_mapping3) do
      create(
        :netsuite_collection_mapping,
        integration:,
        mapping_type: :subscription_fee,
        settings: {external_id: "3", external_account_code: "33", external_name: ""}
      )
    end

    let(:integration_collection_mapping4) do
      create(
        :netsuite_collection_mapping,
        integration:,
        mapping_type: :minimum_commitment,
        settings: {external_id: "4", external_account_code: "44", external_name: ""}
      )
    end

    let(:integration_collection_mapping6) do
      create(
        :netsuite_collection_mapping,
        integration:,
        mapping_type: :prepaid_credit,
        settings: {external_id: "6", external_account_code: "66", external_name: ""}
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

    let(:integration_mapping_bm) do
      create(
        :netsuite_mapping,
        integration:,
        mappable_type: "BillableMetric",
        mappable_id: billable_metric.id,
        settings: {external_id: "m2", external_account_code: "m22", external_name: ""}
      )
    end

    let(:invoice) do
      create(
        :invoice,
        customer:,
        organization:,
        coupons_amount_cents: 2000,
        prepaid_credit_amount_cents: 4000,
        progressive_billing_credit_amount_cents: 100,
        credit_notes_amount_cents: 6000,
        taxes_amount_cents: 200,
        issuing_date: DateTime.new(2024, 7, 8)
      )
    end

    let(:fee_sub) do
      create(
        :fee,
        invoice:,
        amount_cents: 10_000,
        taxes_amount_cents: 200,
        created_at: current_time - 3.seconds
      )
    end

    let(:minimum_commitment_fee) do
      create(
        :minimum_commitment_fee,
        invoice:,
        created_at: current_time - 2.seconds
      )
    end

    let(:charge_fee) do
      create(
        :charge_fee,
        invoice:,
        charge:,
        units: 2,
        precise_unit_amount: 4.12121212123337777,
        created_at: current_time
      )
    end

    let(:body) do
      [
        {
          "external_contact_id" => integration_customer.external_customer_id,
          "status" => "AUTHORISED",
          "issuing_date" => "2024-07-08T00:00:00Z",
          "payment_due_date" => "2024-07-08T00:00:00Z",
          "number" => invoice.number,
          "currency" => "EUR",
          "type" => "ACCREC",
          "fees" => [
            {
              "external_id" => "3",
              "description" => "Subscription",
              "units" => 0.0,
              "precise_unit_amount" => 0.0,
              "account_code" => "33",
              "taxes_amount_cents" => 200
            },
            {
              "external_id" => "4",
              "description" => minimum_commitment_fee.invoice_name,
              "units" => 0.0,
              "precise_unit_amount" => 0.0,
              "account_code" => "44",
              "taxes_amount_cents" => 2
            },
            {
              "external_id" => "m2",
              "description" => charge_fee.invoice_name,
              "units" => 1,
              "amount_cents" => charge_fee.amount_cents,
              "account_code" => "m22",
              "taxes_amount_cents" => 2
            },
            {
              "account_code" => "22",
              "description" => "Coupons",
              "external_id" => "2",
              "precise_unit_amount" => -20.0,
              "taxes_amount_cents" => -4,
              "units" => 1
            },
            {
              "external_id" => "6",
              "description" => "Prepaid credit",
              "units" => 1,
              "precise_unit_amount" => -40.0,
              "taxes_amount_cents" => 0,
              "account_code" => "66"
            },
            {
              "external_id" => "6",
              "description" => "Usage already billed",
              "units" => 1,
              "precise_unit_amount" => -1.0,
              "taxes_amount_cents" => 0,
              "account_code" => "66"
            },
            {
              "external_id" => "1",
              "description" => "Credit note",
              "units" => 1,
              "precise_unit_amount" => -60.0,
              "taxes_amount_cents" => 0,
              "account_code" => "11"
            }
          ]
        }
      ]
    end

    before do
      integration_customer
      charge
      integration_collection_mapping1
      integration_collection_mapping2
      integration_collection_mapping3
      integration_collection_mapping4
      integration_collection_mapping6
      integration_mapping_add_on
      integration_mapping_bm
      fee_sub
      minimum_commitment_fee
      charge_fee
    end

    it "returns payload body" do
      expect(subject).to eq(body)
    end
  end
end
