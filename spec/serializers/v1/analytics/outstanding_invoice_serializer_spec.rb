# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::Analytics::OutstandingInvoiceSerializer do
  subject(:serializer) { described_class.new(outstanding_invoice, root_name: 'outstanding_invoice') }

  let(:outstanding_invoice) do
    {
      'month' => Time.current.beginning_of_month.iso8601,
      'payment_status' => 'succeeded',
      'invoices_count' => 1,
      'currency' => 'EUR',
      'amount_cents' => 100,
    }
  end

  let(:result) { JSON.parse(serializer.to_json) }

  it 'serializes the outstanding invoice' do
    aggregate_failures do
      expect(result['outstanding_invoice']['month']).to eq(Time.current.beginning_of_month.iso8601)
      expect(result['outstanding_invoice']['payment_status']).to eq('succeeded')
      expect(result['outstanding_invoice']['invoices_count']).to eq(1)
      expect(result['outstanding_invoice']['currency']).to eq('EUR')
      expect(result['outstanding_invoice']['amount_cents']).to eq(100)
    end
  end
end
