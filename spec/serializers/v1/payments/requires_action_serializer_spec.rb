# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::Payments::RequiresActionSerializer do
  subject(:serializer) { described_class.new(payment, params) }

  let(:payment) { create(:payment, :requires_action) }
  let(:params) do
    {
      root_name: 'payment',
      provider_customer_id: payment.payment_provider_customer.id
    }
  end

  it 'serializes the object' do
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
      expect(result['payment']['lago_payable_id']).to eq(payment.payable.id)
      expect(result['payment']['lago_customer_id']).to eq(payment.payable.customer.id)
      expect(result['payment']['status']).to eq(payment.status)
      expect(result['payment']['external_customer_id']).to eq(payment.payable.customer.external_id)
      expect(result['payment']['provider_customer_id']).to eq(payment.payment_provider_customer.id)
      expect(result['payment']['payment_provider_code']).to eq(payment.payment_provider.code)
      expect(result['payment']['payment_provider_type']).to eq(payment.payment_provider.type)
      expect(result['payment']['provider_payment_id']).to eq(payment.provider_payment_id)
      expect(result['payment']['next_action']).to eq(payment.provider_payment_data)
    end
  end
end
