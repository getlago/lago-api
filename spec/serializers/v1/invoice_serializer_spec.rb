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
      expect(result['invoice']).to include(
        'lago_id' => invoice.id,
        'sequential_id' => invoice.sequential_id,
        'number' => invoice.number,
        'issuing_date' => invoice.issuing_date.iso8601,
        'invoice_type' => invoice.invoice_type,
        'status' => invoice.status,
        'payment_status' => invoice.payment_status,
        'currency' => invoice.currency,
        'amount_cents' => invoice.amount_cents,
        'fees_amount_cents' => invoice.fees_amount_cents,
        'coupons_amount_cents' => invoice.coupons_amount_cents,
        'credit_notes_amount_cents' => invoice.credit_notes_amount_cents,
        'prepaid_credit_amount_cents' => invoice.prepaid_credit_amount_cents,
        'vat_amount_cents' => invoice.vat_amount_cents,
        'credit_amount_cents' => invoice.credit_amount_cents,
        'total_amount_cents' => invoice.total_amount_cents,
        'file_url' => invoice.file_url,
        'version_number' => 2,

        # NOTE: deprecated fields
        'legacy' => false,
        'amount_currency' => invoice.currency,
        'vat_amount_currency' => invoice.currency,
        'credit_amount_currency' => invoice.currency,
        'total_amount_currency' => invoice.currency,
      )

      expect(result['invoice']['metadata'].first).to include(
        'lago_id' => metadata.id,
        'key' => metadata.key,
        'value' => metadata.value,
      )
    end
  end
end
