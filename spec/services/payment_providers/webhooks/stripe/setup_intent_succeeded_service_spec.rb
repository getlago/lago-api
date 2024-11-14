# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviders::Webhooks::Stripe::SetupIntentSucceededService, type: :service do
  subject(:webhook_service) { described_class.new(organization_id: organization.id, event_json:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:event_json) { File.read('spec/fixtures/stripe/setup_intent_event.json') }

  let(:event) { Stripe::Event.construct_from(JSON.parse(event_json)) }
  let(:provider_customer_id) { event.data.object.customer }
  let(:payment_method_id) { event.data.object.payment_method }

  let(:stripe_provider) { create(:stripe_provider, organization:) }
  let(:stripe_customer) do
    create(:stripe_customer, payment_provider: stripe_provider, customer:, provider_customer_id:)
  end

  before { stripe_customer }

  describe '#call' do
    it 'updates provider default payment method', aggregate_failures: true do
      allow(Stripe::Customer).to receive(:update).and_return(true)

      result = webhook_service.call

      expect(result).to be_success
      expect(result.payment_method_id).to eq(payment_method_id)
      expect(result.stripe_customer).to eq(stripe_customer)
      expect(result.stripe_customer.payment_method_id).to eq(payment_method_id)

      expect(Stripe::Customer).to have_received(:update).with(
        provider_customer_id,
        {invoice_settings: {default_payment_method: payment_method_id}},
        {api_key: stripe_provider.secret_key}
      )
    end

    context 'when stripe customer is not found', aggregate_failures: true do
      let(:provider_customer_id) { 'cus_InvaLid' }

      it 'returns an empty result' do
        result = webhook_service.call

        expect(result).to be_success
        expect(result.payment_method).to be_nil
      end

      context 'when customer in metadata is not found' do
        let(:event_json) { File.read('spec/fixtures/stripe/setup_intent_event_with_metadata.json') }

        it 'returns an empty response', aggregate_failures: true do
          result = webhook_service.call

          expect(result).to be_success
          expect(result.payment_method).to be_nil
        end
      end

      context 'when customer in metadata exists' do
        let(:event_json) { File.read('spec/fixtures/stripe/setup_intent_event_with_metadata.json') }
        let(:customer) { create(:customer, id: event.data.object.metadata['lago_customer_id'], organization:) }

        it 'returns a not found error', aggregate_failures: true do
          result = webhook_service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.message).to eq('stripe_customer_not_found')
        end
      end
    end

    context 'when stripe customer id is nil' do
      let(:event_json) { File.read('spec/fixtures/stripe/setup_intent_event_without_customer.json') }
      let(:provider_customer_id) { 'cus_InvaLid' }

      it 'returns an empty result', aggregate_failures: true do
        result = webhook_service.call

        expect(result).to be_success
        expect(result.payment_method).to be_nil
      end
    end
  end
end
