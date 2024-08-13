# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataExports::Csv::InvoiceFees do
  let(:data_export) do
    create :data_export, :processing, resource_type: 'invoice_fees', resource_query:
  end

  let(:resource_query) do
    {
      currency:,
      customer_id:,
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
  let(:customer_id) { 'customer-lago-id-123' }
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
      "customer_id" => customer_id,
      "invoice_type" => invoice_type,
      "issuing_date_from" => issuing_date_from,
      "issuing_date_to" => issuing_date_to,
      "payment_dispute_lost" => payment_dispute_lost,
      "payment_overdue" => payment_overdue,
      "payment_status" => payment_status,
      "status" => status
    }
  end

  let(:tempfile) { Tempfile.create("test_export") }
  let(:invoice_serializer_klass) { class_double('V1::InvoiceSerializer') }
  let(:fee_serializer_klass) { class_double('V1::FeeSerializer') }
  let(:subscription_serializer_klass) { class_double('V1::SubscriptionSerializer') }

  let(:invoice_serializer) do
    instance_double('V1::InvoiceSerializer', serialize: serialized_invoice)
  end

  let(:fee_serializer) do
    instance_double('V1::FeeSerializer', serialize: serialized_fee)
  end

  let(:subscription_serializer) do
    instance_double('V1::SubscriptionSerializer', serialize: serialized_subscription)
  end

  let(:invoices_query_results) do
    BaseService::Result.new.tap do |result|
      result.invoices = Invoice.all
    end
  end

  let(:invoice) { create :invoice }
  let(:fee) { create :fee, invoice: }

  let(:serialized_invoice) do
    {
      lago_id: "292ef60b-9e0c-42e7-9f50-44d5af4162ec",
      number: "TWI-2B86-170-001",
      issuing_date: "2024-06-06"
    }
  end

  let(:serialized_fee) do
    {
      lago_id: "cc16e6d5-b5e1-4e2c-9ad3-62b3ee4be302",
      item: {
        type: "charge",
        code: "group",
        name: "group",
        description: "charge 1 description",
        invoice_display_name: "group",
        filter_invoice_display_name: "Converted to EUR",
        grouped_by: {models: "model_1"}
      },
      taxes_amount_cents: 50,
      total_amount_cents: 10000,
      total_amount_currency: "USD",
      units: "100.0",
      precise_unit_amount: "10.0",
      from_date: "2024-05-08T00:00:00+00:00",
      to_date: "2024-06-06T12:48:59+00:00"
    }
  end

  let(:serialized_subscription) do
    {
      lago_id: "80ebcc26-3703-4577-b13e-765591255df4",
      external_id: "ff6c279c-9f6c-4962-987e-270936d52310",
      plan_code: "all_charges"
    }
  end

  before do
    invoice
    fee

    allow(invoice_serializer_klass)
      .to receive(:new)
      .and_return(invoice_serializer)

    allow(fee_serializer_klass)
      .to receive(:new)
      .and_return(fee_serializer)

    allow(subscription_serializer_klass)
      .to receive(:new)
      .and_return(subscription_serializer)

    allow(InvoicesQuery)
      .to receive(:call)
      .with(
        organization: data_export.organization,
        pagination: nil,
        search_term:,
        filters:
      )
      .and_return(invoices_query_results)
  end

  describe '#call' do
    subject(:call) do
      described_class.new(
        data_export:,
        invoice_serializer_klass:,
        fee_serializer_klass:,
        subscription_serializer_klass:,
        output: tempfile
      ).call
    end

    it 'generates the correct CSV output' do
      expected_csv = <<~CSV
        invoice_lago_id,invoice_number,invoice_issuing_date,fee_lago_id,fee_item_type,fee_item_code,fee_item_name,fee_item_description,fee_item_invoice_display_name,fee_item_filter_invoice_display_name,fee_item_grouped_by,subscription_external_id,subscription_plan_code,fee_from_date_utc,fee_to_date_utc,fee_amount_currency,fee_units,fee_precise_unit_amount,fee_taxes_amount_cents,fee_total_amount_cents
        292ef60b-9e0c-42e7-9f50-44d5af4162ec,TWI-2B86-170-001,2024-06-06,cc16e6d5-b5e1-4e2c-9ad3-62b3ee4be302,charge,group,group,charge 1 description,group,Converted to EUR,"{:models=>""model_1""}",ff6c279c-9f6c-4962-987e-270936d52310,all_charges,2024-05-08T00:00:00+00:00,2024-06-06T12:48:59+00:00,USD,100.0,10.0,50,10000
      CSV

      call
      tempfile.rewind
      generated_csv = tempfile.read

      expect(generated_csv).to eq(expected_csv)
    end
  end
end
