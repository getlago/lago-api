# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::Analytics::FinalizedInvoiceSerializer do
  subject(:serializer) { described_class.new(finalized_invoice, root_name: 'finalized_invoice') }

  let(:finalized_invoice) do
    {
      'month' => Time.current.beginning_of_month.iso8601,
      'payment_status' => 'succeeded',
      'invoices_count' => 1,
      'currency' => 'EUR',
      'amount_cents' => 100,
    }
  end

  let(:result) { JSON.parse(serializer.to_json) }

  it 'serializes the finalized invoice' do
    aggregate_failures do
      expect(result['finalized_invoice']['month']).to eq(Time.current.beginning_of_month.iso8601)
      expect(result['finalized_invoice']['payment_status']).to eq('succeeded')
      expect(result['finalized_invoice']['invoices_count']).to eq(1)
      expect(result['finalized_invoice']['currency']).to eq('EUR')
      expect(result['finalized_invoice']['amount_cents']).to eq(100)
    end
  end
end
