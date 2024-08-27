# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentRequests::Payments::PaymentProviders::Factory, type: :service do
  subject(:factory_service) { described_class.new_instance(payable:) }

  let(:payment_provider) { 'stripe' }
  let(:payable) { create(:payment_request, customer:) }
  let(:customer) { create(:customer, payment_provider:) }

  describe '#self.new_instance' do
    context 'when stripe' do
      it 'returns correct class' do
        expect(factory_service.class.to_s).to eq('PaymentRequests::Payments::StripeService')
      end
    end

    context 'when adyen' do
      let(:payment_provider) { 'adyen' }

      it 'returns correct class' do
        expect(factory_service.class.to_s).to eq('PaymentRequests::Payments::AdyenService')
      end
    end

    context 'when gocardless' do
      let(:payment_provider) { 'gocardless' }

      it 'returns correct class' do
        expect(factory_service.class.to_s).to eq('PaymentRequests::Payments::GocardlessService')
      end
    end
  end
end
