# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Events::ValidateCreationService, type: :service do
  subject(:validate_event) do
    described_class.call(
      organization:,
      params:,
      result:,
      customer:,
      subscriptions: [subscription],
    )
  end

  let(:organization) { create(:organization) }
  let(:result) { BaseService::Result.new }
  let(:customer) { create(:customer, organization:) }
  let!(:subscription) { create(:subscription, customer:, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:transaction_id) { SecureRandom.uuid }
  let(:params) do
    {external_customer_id: customer.external_id, code: billable_metric.code, transaction_id:}
  end

  describe '.call' do
    context 'when customer has only one active subscription and external_subscription_id is not given' do
      it 'does not return any validation errors' do
        expect(validate_event).to be_nil
        expect(result).to be_success
      end
    end

    context 'when customer has only one active subscription and customer is not given' do
      let(:params) do
        {code: billable_metric.code, external_subscription_id: subscription.external_id, transaction_id:}
      end

      it 'does not return any validation errors' do
        expect(validate_event).to be_nil
        expect(result).to be_success
      end
    end

    context 'when customer has two active subscriptions' do
      before { create(:subscription, customer:, organization:) }

      let(:params) do
        {code: billable_metric.code, external_subscription_id: subscription.external_id, transaction_id:}
      end

      it 'does not return any validation errors' do
        expect(validate_event).to be_nil
        expect(result).to be_success
      end
    end

    context 'when customer is not given but subscription is present' do
      let(:params) do
        {code: billable_metric.code, transaction_id:}
      end

      let(:validate_event) do
        described_class.call(
          organization:,
          params:,
          result:,
          customer: nil,
          subscriptions: [subscription],
        )
      end

      it 'does not return any validation errors' do
        expect(validate_event).to be_nil
        expect(result).to be_success
      end
    end

    context 'when there are two active subscriptions but external_subscription_id is not given' do
      let(:subscription2) { create(:subscription, customer:, organization:) }

      let(:validate_event) do
        described_class.call(
          organization:,
          params:,
          result:,
          customer:,
          subscriptions: [subscription, subscription2],
        )
      end

      it 'returns a subscription_not_found error' do
        validate_event

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.message).to eq('subscription_not_found')
        end
      end
    end

    context 'when there are two active subscriptions but external_subscription_id is invalid' do
      let(:params) do
        {
          code: billable_metric.code,
          external_subscription_id: SecureRandom.uuid,
          external_customer_id: customer.external_id,
          transaction_id:
        }
      end

      let(:subscription2) { create(:subscription, customer:, organization:) }

      let(:validate_event) do
        described_class.call(
          organization:,
          params:,
          result:,
          customer:,
          subscriptions: [subscription, subscription2],
        )
      end

      it 'returns a not found error' do
        validate_event

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.message).to eq('subscription_not_found')
        end
      end
    end

    context 'when there is one active subscription with the same external_id' do
      let(:subscription) do
        create(:subscription, customer:, organization:, external_id:, status: :terminated)
      end
      let(:external_id) { SecureRandom.uuid }
      let(:params) do
        {
          code: billable_metric.code,
          external_subscription_id: external_id,
          external_customer_id: customer.external_id,
          transaction_id:
        }
      end

      before do
        subscription
        create(:subscription, customer:, organization:, external_id:)
      end

      it 'does not return any validation errors' do
        expect(validate_event).to be_nil
        expect(result).to be_success
      end
    end

    context 'when transaction_id is already used' do
      before do
        create(
          :event,
          transaction_id:,
          external_subscription_id: subscription.external_id,
          subscription_id: subscription.id,
          organization_id: organization.id,
        )
      end

      it 'returns a validation error' do
        validate_event

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages.keys).to include(:transaction_id)
        expect(result.error.messages[:transaction_id]).to include('value_is_missing_or_already_exists')
      end
    end

    context 'when code does not exist' do
      let(:params) do
        {external_customer_id: customer.external_id, code: 'event_code', transaction_id:}
      end

      it 'returns an event_not_found error' do
        validate_event

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.message).to eq('billable_metric_not_found')
        end
      end
    end

    context 'when field_name value is not a number' do
      let(:billable_metric) { create(:sum_billable_metric, organization:) }
      let(:params) do
        {
          code: billable_metric.code,
          external_customer_id: customer.external_id,
          properties: {
            item_id: 'test'
          },
          transaction_id:
        }
      end

      it 'returns an value_is_not_valid_number error' do
        validate_event

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages.keys).to include(:properties)
          expect(result.error.messages[:properties]).to include('value_is_not_valid_number')
        end
      end

      context 'when field_name cannot be found' do
        let(:params) do
          {
            code: billable_metric.code,
            external_customer_id: customer.external_id,
            properties: {
              invalid_key: 'test'
            },
            transaction_id:
          }
        end

        it 'does not raise error' do
          validate_event

          expect(result).to be_success
        end
      end

      context 'when properties are missing' do
        let(:params) do
          {
            code: billable_metric.code,
            external_customer_id: customer.external_id,
            transaction_id:
          }
        end

        it 'does not raise error' do
          validate_event

          expect(result).to be_success
        end
      end
    end
  end
end
