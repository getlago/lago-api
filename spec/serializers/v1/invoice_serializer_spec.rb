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
        'payment_due_date' => invoice.payment_due_date.iso8601,
        'net_payment_term' => invoice.net_payment_term,
        'invoice_type' => invoice.invoice_type,
        'status' => invoice.status,
        'payment_status' => invoice.payment_status,
        'payment_dispute_lost_at' => invoice.payment_dispute_lost_at,
        'payment_overdue' => invoice.payment_overdue,
        'currency' => invoice.currency,
        'fees_amount_cents' => invoice.fees_amount_cents,
        'coupons_amount_cents' => invoice.coupons_amount_cents,
        'credit_notes_amount_cents' => invoice.credit_notes_amount_cents,
        'prepaid_credit_amount_cents' => invoice.prepaid_credit_amount_cents,
        'taxes_amount_cents' => invoice.taxes_amount_cents,
        'sub_total_excluding_taxes_amount_cents' => invoice.sub_total_excluding_taxes_amount_cents,
        'sub_total_including_taxes_amount_cents' => invoice.sub_total_including_taxes_amount_cents,
        'total_amount_cents' => invoice.total_amount_cents,
        'file_url' => invoice.file_url,
        'version_number' => 4
      )

      expect(result['invoice']['metadata'].first).to include(
        'lago_id' => metadata.id,
        'key' => metadata.key,
        'value' => metadata.value
      )
    end
  end
end
