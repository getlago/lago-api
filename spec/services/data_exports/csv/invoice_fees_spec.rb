# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataExports::Csv::InvoiceFees do
  let(:data_export) do
    create :data_export, :processing, resource_type: 'invoice_fees', resource_query:
  end

  let(:resource_query) do
    {
      currency:,
      customer_external_id:,
      invoice_type:,
      issuing_date_from:,
      issuing_date_to:,
      payment_dispute_lost:,
      payment_overdue:,
      payment_status:,
      search_term:,
      status:
    }
  end

  let(:currency) { 'EUR' }
  let(:customer_external_id) { 'custext123' }
  let(:invoice_type) { 'credit' }
  let(:issuing_date_from) { '2023-12-25' }
  let(:issuing_date_to) { '2024-07-01' }
  let(:payment_dispute_lost) { false }
  let(:payment_overdue) { true }
  let(:payment_status) { 'pending' }
  let(:search_term) { 'service ABC' }
  let(:status) { 'finalized' }

  let(:filters) do
    {
      "currency" => currency,
      "customer_external_id" => customer_external_id,
      "invoice_type" => invoice_type,
      "issuing_date_from" => issuing_date_from,
      "issuing_date_to" => issuing_date_to,
      "payment_dispute_lost" => payment_dispute_lost,
      "payment_overdue" => payment_overdue,
      "payment_status" => payment_status
    }
  end

  let(:serializer_klass) { class_double('V1::InvoiceSerializer') }
  let(:invoice_serializer) do
    instance_double('V1::InvoiceSerializer', serialize: serialized_invoice)
  end

  let(:invoices_query) { instance_double('InvoicesQuery') }
  let(:query_results) do
    BaseService::Result.new.tap do |result|
      result.invoices = Invoice.all
    end
  end

  let(:invoice) { create :invoice }
  let(:serialized_invoice) do
    {
      lago_id: "292ef60b-9e0c-42e7-9f50-44d5af4162ec",
      number: "TWI-2B86-170-001",
      issuing_date: "2024-06-06",
      subscriptions: [
        {
          lago_id: "80ebcc26-3703-4577-b13e-765591255df4",
          external_id: "ff6c279c-9f6c-4962-987e-270936d52310",
          plan_code: "all_charges"
        }
      ],
      fees: [
        {
          lago_id: "cc16e6d5-b5e1-4e2c-9ad3-62b3ee4be302",
          lago_subscription_id: "80ebcc26-3703-4577-b13e-765591255df4",
          item: {
            type: "charge",
            code: "group",
            name: "group",
            invoice_display_name: "group",
            filter_invoice_display_name: "Converted to EUR",
            grouped_by: {
              models: "model_1"
            }
          },
          taxes_amount_cents: 0,
          total_amount_cents: 10000,
          total_amount_currency: "USD",
          units: "100.0",
          precise_unit_amount: "1.0",
          from_date: "2024-05-08T00:00:00+00:00",
          to_date: "2024-06-06T12:48:59+00:00"
        },
        {
          lago_id: "5277b901-3da6-4a55-974a-ee1295978e98",
          lago_subscription_id: "80ebcc26-3703-4577-b13e-765591255df4",
          item: {
            type: "charge",
            code: "group",
            name: "group",
            invoice_display_name: "group",
            filter_invoice_display_name: nil,
            grouped_by: {
              models: "model_2"
            }
          },
          taxes_amount_cents: 0,
          total_amount_cents: 20000,
          total_amount_currency: "USD",
          units: "200.0",
          precise_unit_amount: "1.0",
          from_date: "2024-05-08T00:00:00+00:00",
          to_date: "2024-06-06T12:48:59+00:00"
        },
        {
          lago_id: "86d3515f-2c4e-49de-9e81-99f8c22f38ad",
          lago_subscription_id: "80ebcc26-3703-4577-b13e-765591255df4",
          item: {
            type: "charge",
            code: "group",
            name: "group",
            invoice_display_name: "group",
            filter_invoice_display_name: nil,
            grouped_by: {
              models: "model_3"
            }
          },
          taxes_amount_cents: 0,
          total_amount_cents: 30000,
          total_amount_currency: "USD",
          units: "300.0",
          precise_unit_amount: "1.0",
          from_date: "2024-05-08T00:00:00+00:00",
          to_date: "2024-06-06T12:48:59+00:00"
        },
        {
          lago_id: "203e6d6b-a5ff-4eb5-bbb9-01bfdf4f8d22",
          lago_subscription_id: "80ebcc26-3703-4577-b13e-765591255df4",
          item: {
            type: "charge",
            code: "filters",
            name: "filters",
            invoice_display_name: "filters",
            filter_invoice_display_name: "model_1, input",
            grouped_by: {}
          },
          taxes_amount_cents: 0,
          total_amount_cents: 0,
          total_amount_currency: "USD",
          units: "0.0",
          precise_unit_amount: "0.0",
          from_date: "2024-05-08T00:00:00+00:00",
          to_date: "2024-06-06T12:48:59+00:00"
        },
        {
          lago_id: "af3b0a41-33c3-4f2c-a6e4-62402df59ee3",
          lago_subscription_id: "80ebcc26-3703-4577-b13e-765591255df4",
          item: {
            type: "charge",
            code: "filters",
            name: "filters",
            invoice_display_name: "filters",
            filter_invoice_display_name: "model_2, output",
            grouped_by: {}
          },
          taxes_amount_cents: 0,
          total_amount_cents: 0,
          total_amount_currency: "USD",
          units: "0.0",
          precise_unit_amount: "0.0",
          from_date: "2024-05-08T00:00:00+00:00",
          to_date: "2024-06-06T12:48:59+00:00"
        },
        {
          lago_id: "282867c6-fa26-4c08-82b4-42d4128d4627",
          lago_subscription_id: nil,
          item: {
            type: "charge",
            code: "filters",
            name: "filters",
            invoice_display_name: "filters",
            filter_invoice_display_name: nil,
            grouped_by: {}
          },
          taxes_amount_cents: 0,
          total_amount_cents: 0,
          total_amount_currency: "USD",
          units: "0.0",
          precise_unit_amount: "0.0",
          from_date: "2024-05-08T00:00:00+00:00",
          to_date: "2024-06-06T12:48:59+00:00"
        }
      ]
    }
  end

  before do
    invoice

    allow(serializer_klass)
      .to receive(:new)
      .and_return(invoice_serializer)

    allow(InvoicesQuery)
      .to receive(:new)
      .with(organization: data_export.organization)
      .and_return(invoices_query)

    allow(invoices_query)
      .to receive(:call)
      .with(
        search_term:,
        status:,
        filters:
      )
      .and_return(query_results)
  end

  describe '#call' do
    subject(:call) { described_class.new(data_export:, serializer_klass:).call }

    it 'generates the correct CSV output' do
      expected_csv = <<~CSV
        invoice_lago_id,invoice_number,invoice_issuing_date,fee_lago_id,fee_item_type,fee_item_code,fee_item_name,fee_item_invoice_display_name,fee_item_filter_invoice_display_name,fee_item_grouped_by,subscription_external_id,subscription_plan_code,fee_from_date,fee_to_date,fee_total_amount_cents,fee_amount_currency,fee_units,fee_precise_unit_amount,fee_taxes_amount_cents
        292ef60b-9e0c-42e7-9f50-44d5af4162ec,TWI-2B86-170-001,2024-06-06,cc16e6d5-b5e1-4e2c-9ad3-62b3ee4be302,charge,group,group,group,Converted to EUR,"{:models=>""model_1""}",ff6c279c-9f6c-4962-987e-270936d52310,all_charges,2024-05-08T00:00:00+00:00,2024-06-06T12:48:59+00:00,10000,USD,100.0,1.0,0
        292ef60b-9e0c-42e7-9f50-44d5af4162ec,TWI-2B86-170-001,2024-06-06,5277b901-3da6-4a55-974a-ee1295978e98,charge,group,group,group,,"{:models=>""model_2""}",ff6c279c-9f6c-4962-987e-270936d52310,all_charges,2024-05-08T00:00:00+00:00,2024-06-06T12:48:59+00:00,20000,USD,200.0,1.0,0
        292ef60b-9e0c-42e7-9f50-44d5af4162ec,TWI-2B86-170-001,2024-06-06,86d3515f-2c4e-49de-9e81-99f8c22f38ad,charge,group,group,group,,"{:models=>""model_3""}",ff6c279c-9f6c-4962-987e-270936d52310,all_charges,2024-05-08T00:00:00+00:00,2024-06-06T12:48:59+00:00,30000,USD,300.0,1.0,0
        292ef60b-9e0c-42e7-9f50-44d5af4162ec,TWI-2B86-170-001,2024-06-06,203e6d6b-a5ff-4eb5-bbb9-01bfdf4f8d22,charge,filters,filters,filters,"model_1, input",{},ff6c279c-9f6c-4962-987e-270936d52310,all_charges,2024-05-08T00:00:00+00:00,2024-06-06T12:48:59+00:00,0,USD,0.0,0.0,0
        292ef60b-9e0c-42e7-9f50-44d5af4162ec,TWI-2B86-170-001,2024-06-06,af3b0a41-33c3-4f2c-a6e4-62402df59ee3,charge,filters,filters,filters,"model_2, output",{},ff6c279c-9f6c-4962-987e-270936d52310,all_charges,2024-05-08T00:00:00+00:00,2024-06-06T12:48:59+00:00,0,USD,0.0,0.0,0
        292ef60b-9e0c-42e7-9f50-44d5af4162ec,TWI-2B86-170-001,2024-06-06,282867c6-fa26-4c08-82b4-42d4128d4627,charge,filters,filters,filters,,{},,,2024-05-08T00:00:00+00:00,2024-06-06T12:48:59+00:00,0,USD,0.0,0.0,0
      CSV

      expect(call).to eq(expected_csv)
    end
  end
end
