# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::CustomerSerializer do
  subject(:serializer) { described_class.new(customer, root_name: 'customer') }

  let(:customer) { create(:customer) }

  it 'serializes the object' do
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
      expect(result['customer']['lago_id']).to eq(customer.id)
      expect(result['customer']['external_id']).to eq(customer.external_id)
      expect(result['customer']['name']).to eq(customer.name)
      expect(result['customer']['sequential_id']).to eq(customer.sequential_id)
      expect(result['customer']['slug']).to eq(customer.slug)
      expect(result['customer']['created_at']).to eq(customer.created_at.iso8601)
      expect(result['customer']['country']).to eq(customer.country)
      expect(result['customer']['address_line1']).to eq(customer.address_line1)
      expect(result['customer']['address_line2']).to eq(customer.address_line2)
      expect(result['customer']['state']).to eq(customer.state)
      expect(result['customer']['zipcode']).to eq(customer.zipcode)
      expect(result['customer']['email']).to eq(customer.email)
      expect(result['customer']['city']).to eq(customer.city)
      expect(result['customer']['url']).to eq(customer.url)
      expect(result['customer']['phone']).to eq(customer.phone)
      expect(result['customer']['logo_url']).to eq(customer.logo_url)
      expect(result['customer']['legal_name']).to eq(customer.legal_name)
      expect(result['customer']['legal_number']).to eq(customer.legal_number)
      expect(result['customer']['currency']).to eq(customer.currency)
      expect(result['customer']['timezone']).to eq(customer.timezone)
      expect(result['customer']['applicable_timezone']).to eq(customer.applicable_timezone)
      expect(result['customer']['billing_configuration']['payment_provider']).to eq(customer.payment_provider)
      expect(result['customer']['billing_configuration']['invoice_grace_period']).to eq(customer.invoice_grace_period)
      expect(result['customer']['billing_configuration']['vat_rate']).to eq(customer.vat_rate)
    end
  end
end
