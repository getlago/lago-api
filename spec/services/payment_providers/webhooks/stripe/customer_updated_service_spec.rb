# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviders::Webhooks::Stripe::CustomerUpdatedService, type: :service do
  subject(:webhook_service) { described_class.new(organization_id: organization.id, event_json:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:event_json) { File.read('spec/fixtures/stripe/customer_updated_event.json') }

  let(:event) { Stripe::Event.construct_from(JSON.parse(event_json)) }
  let(:provider_customer_id) { event.data.object.id }
  let(:payment_method_id) { event.data.object.default_source }

  let(:stripe_provider) { create(:stripe_provider, organization:) }
  let(:stripe_customer) do
    create(:stripe_customer, payment_provider: stripe_provider, customer:, provider_customer_id:)
  end

  before { stripe_customer }

  describe '#call' do
    it 'updates the customer payment method', aggregate_failures: true do
      result = webhook_service.call

      expect(result).to be_success
      expect(result.stripe_customer.payment_method_id).to eq(payment_method_id)
    end

    context 'when customer is not found' do
      let(:provider_customer_id) { 'cus_InvaLid' }

      it 'returns an empty result', aggregate_failures: true do
        result = webhook_service.call

        expect(result).to be_success
        expect(result.stripe_customer).to be_nil
      end

      context 'when customer in metadata is not found' do
        let(:event_json) { File.read('spec/fixtures/stripe/customer_updated_event_with_metadata.json') }

        it 'returns an empty response', aggregate_failures: true do
          result = webhook_service.call

          expect(result).to be_success
          expect(result.stripe_customer).to be_nil
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
  end
end
