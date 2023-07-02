# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviderCustomers::StripeCustomer, type: :model do
  subject(:stripe_customer) { described_class.new(attributes) }

  let(:attributes) {}

  describe 'payment_method_id' do
    it 'assigns and retrieve a payment method id' do
      stripe_customer.payment_method_id = 'foo_bar'
      expect(stripe_customer.payment_method_id).to eq('foo_bar')
    end
  end

  describe '#provider_payment_methods' do
    subject(:provider_payment_methods) { stripe_customer.provider_payment_methods }

    let(:stripe_customer) { FactoryBot.build_stubbed(:stripe_customer) }

    let(:payment_methods) do
      described_class::ALLOWED_PAYMENT_METHODS.sample Faker::Number.between(from: 1, to: 2)
    end

    before { stripe_customer.provider_payment_methods = payment_methods }

    it 'returns provider payment methods' do
      expect(provider_payment_methods).to eq payment_methods
    end
  end

  describe 'validation' do
    describe 'of provider payment methods' do
      subject(:stripe_customer) do
        FactoryBot.build_stubbed(:stripe_customer, provider_payment_methods:)
      end

      context 'when it is an empty array' do
        let(:provider_payment_methods) { [] }

        it 'is invalid' do
          expect(stripe_customer).to be_invalid
        end
      end

      context 'when it is nil' do
        let(:provider_payment_methods) { nil }

        it 'is invalid' do
          expect(stripe_customer).to be_invalid
        end
      end

      context 'when it contains invalid value' do
        let(:provider_payment_methods) { %w[invalid] }

        it 'is invalid' do
          expect(stripe_customer).to be_invalid
        end
      end

      context 'when it contains both valid and invalid values' do
        let(:provider_payment_methods) { %w[card cash] }

        it 'is invalid' do
          expect(stripe_customer).to be_invalid
        end
      end

      context 'when it contains valid value' do
        let(:provider_payment_methods) { %w[card] }

        it 'is valid' do
          expect(stripe_customer).to be_valid
        end
      end

      context 'when it contains multiple valid values' do
        let(:provider_payment_methods) { described_class::ALLOWED_PAYMENT_METHODS }

        it 'is valid' do
          expect(stripe_customer).to be_valid
        end
      end
    end
  end
end
