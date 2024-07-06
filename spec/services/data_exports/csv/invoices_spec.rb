require 'rails_helper'

RSpec.describe DataExports::Csv::Invoices do
  let(:data_export) { create :data_export, :processing, resource_query: }

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
      lago_id: '1',
      sequential_id: 'SEQ123',
      issuing_date: '2023-01-01',
      customer: {
        external_id: 'CUST123',
        country: 'US',
        tax_identification_number: '123456789'
      },
      number: 'INV123',
      total_amount_cents: 1000,
      currency: 'USD',
      invoice_type: 'credit',
      payment_status: 'pending',
      status: 'finalized',
      file_url: 'http://api.lago.com/invoice.pdf',
      taxes_amount_cents: 200,
      credit_notes_amount_cents: 100,
      prepaid_credit_amount_cents: 50,
      coupons_amount_cents: 25,
      payment_due_date: '2023-02-01',
      payment_dispute_lost_at: nil,
      payment_overdue: false
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
        page: nil,
        limit: nil,
        filters:
      )
      .and_return(query_results)
  end

  describe '#call' do
    subject(:call) do
      described_class.new(
        data_export: data_export,
        serializer_klass: serializer_klass
      ).call
    end

    it 'generates the correct CSV output' do
      expected_csv = <<~CSV
        lago_id,sequential_id,issuing_date,customer_lago_id,customer_external_id,customer_country,customer_tax_identification_number,invoince_number,total_amount_cents,currency,invoice_type,payment_status,status,file_url,taxes_amount_cents,credit_notes_amount_cents,prepaid_credit_amount_cents,coupons_amount_cents,payment_due_date,payment_dispute_lost_at,payment_overdue
        1,SEQ123,2023-01-01,,CUST123,US,123456789,INV123,1000,USD,credit,pending,finalized,http://api.lago.com/invoice.pdf,200,100,50,25,2023-02-01,,false
      CSV

      expect(call).to eq(expected_csv)
    end
  end
end
