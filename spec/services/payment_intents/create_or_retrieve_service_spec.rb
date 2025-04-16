# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentIntents::CreateOrRetrieveService, type: :service do
  subject(:create_service) { described_class.new(payable: invoice, payment_provider: payment_provider) }

  let(:invoice) { create(:invoice) }
  let(:payment_provider) { create(:stripe_provider) }

  describe '#call' do
    context 'when no active payment intent exists' do
      it 'creates a new payment intent' do
        expect { create_service.call }
          .to change(PaymentIntent, :count).by(1)

        result = create_service.call
        expect(result).to be_success
        expect(result.payment_intent).to be_present
        expect(result.payment_intent.payable).to eq(invoice)
        expect(result.payment_intent.payment_provider).to eq(payment_provider)
        expect(result.payment_intent.status).to eq('pending')
        expect(result.payment_intent.expires_at).to be_within(1.second).of(24.hours.from_now)
      end
    end

    context 'when an active payment intent exists' do
      let!(:existing_intent) do
        create(:payment_intent,
          payable: invoice,
          payment_provider: payment_provider,
          expires_at: 23.hours.from_now
        )
      end

      it 'returns the existing payment intent' do
        expect { create_service.call }
          .not_to change(PaymentIntent, :count)

        result = create_service.call
        expect(result).to be_success
        expect(result.payment_intent).to eq(existing_intent)
      end
    end

    context 'when only expired payment intents exist' do
      let!(:expired_intent) do
        create(:payment_intent,
          payable: invoice,
          payment_provider: payment_provider,
          expires_at: 1.hour.ago
        )
      end

      it 'creates a new payment intent' do
        expect { create_service.call }
          .to change(PaymentIntent, :count).by(1)

        result = create_service.call
        expect(result).to be_success
        expect(result.payment_intent).not_to eq(expired_intent)
        expect(result.payment_intent.payable).to eq(invoice)
        expect(result.payment_intent.payment_provider).to eq(payment_provider)
      end
    end
  end
end 