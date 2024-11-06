# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataExports::Csv::Invoices do
  let(:data_export) { create :data_export, :processing, resource_query: }

  let(:data_export_part) { data_export.data_export_parts.create(object_ids: [invoice.id], index: 1) }

  let(:resource_query) do
    {
      currency:,
      customer_external_id:,
      customer_id:,
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
  let(:customer_id) { 'customer-lago-id-123' }
  let(:customer_external_id) { 'custext123' }
  let(:invoice_type) { 'credit' }
  let(:issuing_date_from) { '2023-12-25' }
  let(:issuing_date_to) { '2024-07-01' }
  let(:payment_dispute_lost) { false }
  let(:payment_overdue) { true }
  let(:payment_status) { 'pending' }
  let(:search_term) { 'service ABC' }
  let(:status) { 'finalized' }

  let(:serializer_klass) { class_double('V1::InvoiceSerializer') }
  let(:invoice_serializer) do
    instance_double('V1::InvoiceSerializer', serialize: serialized_invoice)
  end

  let(:invoice) { create :invoice }
  let(:serialized_invoice) do
    {
      lago_id: 'invoice-lago-id-123',
      sequential_id: 'SEQ123',
      issuing_date: '2023-01-01',
      customer: {
        name: 'customer name',
        lago_id: 'customer-lago-id-456',
        external_id: 'CUST123',
        country: 'US',
        tax_identification_number: '123456789'
      },
      number: 'INV123',
      invoice_type: 'credit',
      payment_status: 'pending',
      status: 'finalized',
      file_url: 'http://api.lago.com/invoice.pdf',
      currency: 'USD',
      fees_amount_cents: 70000,
      coupons_amount_cents: 1655,
      taxes_amount_cents: 10500,
      credit_notes_amount_cents: 334,
      prepaid_credit_amount_cents: 1000,
      total_amount_cents: 77511,
      payment_due_date: '2023-02-01',
      payment_dispute_lost_at: '2023-12-22',
      payment_overdue: false
    }
  end

  before do
    invoice

    allow(serializer_klass)
      .to receive(:new)
      .and_return(invoice_serializer)
  end

  describe '#call' do
    subject(:result) do
      described_class.new(data_export_part:, serializer_klass:).call
    end

    it 'generates the correct CSV output' do
      expected_csv = <<~CSV
        invoice-lago-id-123,SEQ123,2023-01-01,customer-lago-id-456,CUST123,customer name,US,123456789,INV123,credit,pending,finalized,http://api.lago.com/invoice.pdf,USD,70000,1655,10500,334,1000,77511,2023-02-01,2023-12-22,false
      CSV

      expect(result).to be_success
      file = result.csv_file
      generated_csv = file.read

      file.close
      File.unlink(file.path)
      expect(generated_csv).to eq(expected_csv)
    end
  end
end
