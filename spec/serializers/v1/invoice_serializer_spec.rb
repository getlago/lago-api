# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::InvoiceSerializer do
  subject(:serializer) { described_class.new(invoice, root_name: 'invoice', includes: %i[metadata]) }

  let(:invoice) { create(:invoice) }
  let(:metadata) { create(:invoice_metadata, invoice:) }

  before { metadata }

  it 'serializes the object' do
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
      expect(result['invoice']['lago_id']).to eq(invoice.id)
      expect(result['invoice']['sequential_id']).to eq(invoice.sequential_id)
      expect(result['invoice']['number']).to eq(invoice.number)
      expect(result['invoice']['issuing_date']).to eq(invoice.issuing_date.iso8601)
      expect(result['invoice']['invoice_type']).to eq(invoice.invoice_type)
      expect(result['invoice']['status']).to eq(invoice.status)
      expect(result['invoice']['payment_status']).to eq(invoice.payment_status)
      expect(result['invoice']['amount_cents']).to eq(invoice.amount_cents)
      expect(result['invoice']['amount_currency']).to eq(invoice.amount_currency)
      expect(result['invoice']['vat_amount_cents']).to eq(invoice.vat_amount_cents)
      expect(result['invoice']['vat_amount_currency']).to eq(invoice.vat_amount_currency)
      expect(result['invoice']['credit_amount_cents']).to eq(invoice.credit_amount_cents)
      expect(result['invoice']['credit_amount_currency']).to eq(invoice.credit_amount_currency)
      expect(result['invoice']['total_amount_cents']).to eq(invoice.total_amount_cents)
      expect(result['invoice']['total_amount_currency']).to eq(invoice.total_amount_currency)
      expect(result['invoice']['file_url']).to eq(invoice.file_url)
      expect(result['invoice']['legacy']).to eq(invoice.legacy)
      expect(result['invoice']['metadata'].first['lago_id']).to eq(metadata.id)
      expect(result['invoice']['metadata'].first['key']).to eq(metadata.key)
      expect(result['invoice']['metadata'].first['value']).to eq(metadata.value)
    end
  end
end
