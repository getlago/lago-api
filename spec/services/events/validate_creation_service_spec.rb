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
      batch:,
    )
  end

  let(:organization) { create(:organization) }
  let(:result) { BaseService::Result.new }
  let(:customer) { create(:customer, organization:) }
  let!(:subscription) { create(:active_subscription, customer:, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:transaction_id) { SecureRandom.uuid }
  let(:params) do
    { external_customer_id: customer.external_id, code: billable_metric.code, transaction_id: }
  end

  describe '.call' do
    context 'when batch is false' do
      let(:batch) { false }

      context 'when customer has only one active subscription and external_subscription_id is not given' do
        it 'does not return any validation errors' do
          expect(validate_event).to be_nil
          expect(result).to be_success
        end
      end

      context 'when customer has only one active subscription and customer is not given' do
        let(:params) do
          { code: billable_metric.code, external_subscription_id: subscription.external_id, transaction_id: }
        end

        it 'does not return any validation errors' do
          expect(validate_event).to be_nil
          expect(result).to be_success
        end
      end

      context 'when customer has two active subscriptions' do
        before { create(:active_subscription, customer:, organization:) }

        let(:params) do
          { code: billable_metric.code, external_subscription_id: subscription.external_id, transaction_id: }
        end

        it 'does not return any validation errors' do
          expect(validate_event).to be_nil
          expect(result).to be_success
        end
      end

      context 'when customer is not given but subscription is present' do
        let(:params) do
          { code: billable_metric.code, transaction_id: }
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
        let(:subscription2) { create(:active_subscription, customer:, organization:) }

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
            transaction_id:,
          }
        end

        let(:subscription2) { create(:active_subscription, customer:, organization:) }

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
            transaction_id:,
          }
        end

        before do
          subscription
          create(:active_subscription, customer:, organization:, external_id:)
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
          { external_customer_id: customer.external_id, code: 'event_code', transaction_id: }
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
              item_id: 'test',
            },
            transaction_id:,
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
                invalid_key: 'test',
              },
              transaction_id:,
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
              transaction_id:,
            }
          end

          it 'does not raise error' do
            validate_event

            expect(result).to be_success
          end
        end
      end

      context 'when event belongs to a unique count persisted event' do
        let(:billable_metric) do
          create(
            :billable_metric,
            organization:,
            aggregation_type: 'unique_count_agg',
            field_name: 'item_id',
          )
        end

        let(:params) do
          {
            customer_id: customer.external_id,
            code: billable_metric.code,
            properties: {
              billable_metric.field_name => 'ext_1234',
              'operation_type' => operation_type,
            },
            transaction_id:,
          }
        end

        let(:operation_type) { 'add' }

        it 'returns no error' do
          validate_event

          expect(result).to be_success
        end

        context 'when params are invalid' do
          let(:operation_type) { 'invalid' }

          it 'returns invalid recurring resource error' do
            validate_event

            aggregate_failures do
              expect(result).not_to be_success
              expect(result.error).to be_a(BaseService::ValidationFailure)
              expect(result.error.messages.keys).to include(:operation_type)
              expect(result.error.messages[:operation_type]).to eq(['invalid_operation_type'])
            end
          end
        end
      end

      context 'when event belongs to a unique count persisted event and subscription is terminated' do
        let(:billable_metric) do
          create(
            :billable_metric,
            organization:,
            aggregation_type: 'unique_count_agg',
            field_name: 'item_id',
          )
        end

        let(:subscription) { create(:subscription, customer:, organization:, status: :terminated) }
        let(:params) do
          {
            external_subscription_id: subscription.external_id,
            code: billable_metric.code,
            properties: {
              billable_metric.field_name => 'ext_1234',
              'operation_type' => 'add',
            },
            transaction_id:,
          }
        end

        it 'returns no error' do
          validate_event

          expect(result).to be_success
        end
      end
    end

    context 'when batch is true' do
      let(:batch) { true }

      context 'when everything is passing' do
        let(:params) do
          { external_subscription_ids: [subscription.external_id], code: billable_metric.code }
        end

        it 'does not return any validation errors' do
          expect(validate_event).to be_nil
          expect(result).to be_success
        end
      end

      context 'when external_subscription_ids is blank' do
        let(:params) do
          { external_subscription_ids: [] }
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

      context 'when customer is not given' do
        let(:params) do
          { code: billable_metric.code, external_subscription_ids: [SecureRandom.uuid] }
        end

        let(:validate_event) do
          described_class.call(
            organization:,
            params:,
            result:,
            customer: nil,
            subscriptions: [subscription],
            batch:,
          )
        end

        it 'returns a customer_not_found error' do
          validate_event

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::NotFoundFailure)
            expect(result.error.message).to eq('customer_not_found')
          end
        end
      end

      context 'when there are two active subscriptions but subscription_ids is invalid' do
        let(:params) do
          {
            code: billable_metric.code,
            external_subscription_ids: [SecureRandom.uuid],
            external_customer_id: customer.external_id,
          }
        end

        before do
          create(:active_subscription, customer:, organization:)
        end

        it 'returns subscription is invalid error' do
          validate_event

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::NotFoundFailure)
            expect(result.error.message).to eq('subscription_not_found')
          end
        end
      end

      context 'when code does not exist' do
        let(:params) do
          {
            code: 'event_code',
            external_subscription_ids: [subscription.external_id],
            external_customer_id: customer.external_id,
          }
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

      context 'when properties field_name value is not a number' do
        let(:billable_metric) { create(:sum_billable_metric, organization:) }
        let(:params) do
          {
            code: billable_metric.code,
            external_customer_id: customer.external_id,
            external_subscription_ids: [subscription.external_id],
            properties: {
              item_id: 'test',
            },
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
      end

      context 'when event belongs to a unique count persisted metric' do
        let(:billable_metric) do
          create(
            :billable_metric,
            organization:,
            aggregation_type: 'unique_count_agg',
            field_name: 'item_id',
          )
        end

        let(:params) do
          {
            external_subscription_ids: [subscription.external_id],
            code: billable_metric.code,
            properties: {
              billable_metric.field_name => 'ext_1234',
              'operation_type' => operation_type,
            },
          }
        end

        let(:operation_type) { 'add' }

        it 'returns no error' do
          validate_event

          expect(result).to be_success
        end

        context 'when params are invalid' do
          let(:operation_type) { 'invalid' }

          it 'returns invalid recurring resource error' do
            validate_event

            aggregate_failures do
              expect(result).not_to be_success
              expect(result.error).to be_a(BaseService::ValidationFailure)

              subscription_field = "subscription[#{subscription.external_id}]_operation_type".to_sym
              expect(result.error.messages.keys).to include(subscription_field)
              expect(result.error.messages[subscription_field]).to eq(['invalid_operation_type'])
            end
          end
        end
      end
    end
  end
end
