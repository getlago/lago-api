# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Events::ValidateCreationService, type: :service do
  subject(:validate_event) do
    described_class.call(
      organization: organization,
      params: params,
      result: result,
      customer: customer,
      batch: batch,
    )
  end

  let(:organization) { create(:organization) }
  let(:result) { BaseService::Result.new }
  let(:customer) { create(:customer, organization: organization) }
  let(:billable_metric) { create(:billable_metric, organization: organization) }
  let(:params) do
    { external_customer_id: customer.external_id, code: billable_metric.code }
  end

  describe '.call' do
    let!(:subscription) { create(:active_subscription, customer: customer, organization: organization) }

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
          { code: billable_metric.code, external_subscription_id: subscription.external_id }
        end

        it 'does not return any validation errors' do
          expect(validate_event).to be_nil
          expect(result).to be_success
        end
      end

      context 'when customer has two active subscriptions' do
        before { create(:active_subscription, customer: customer, organization: organization) }

        let(:params) do
          { code: billable_metric.code, external_subscription_id: subscription.external_id }
        end

        it 'does not return any validation errors' do
          expect(validate_event).to be_nil
          expect(result).to be_success
        end
      end

      context 'when customer is not given' do
        let(:params) do
          { code: billable_metric.code }
        end

        let(:validate_event) do
          described_class.call(
            organization: organization,
            params: params,
            result: result,
            customer: nil,
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

        it 'enqueues a SendWebhookJob' do
          expect { validate_event }.to have_enqueued_job(SendWebhookJob)
        end
      end

      context 'when there are two active subscriptions but external_subscription_id is not given' do
        before do
          create(:active_subscription, customer: customer, organization: organization)
        end

        it 'returns a subscription_not_found error' do
          validate_event

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::NotFoundFailure)
            expect(result.error.message).to eq('subscription_not_found')
          end
        end

        it 'enqueues a SendWebhookJob' do
          expect { validate_event }.to have_enqueued_job(SendWebhookJob)
        end
      end

      context 'when there are two active subscriptions but external_subscription_id is invalid' do
        let(:params) do
          {
            code: billable_metric.code,
            external_subscription_id: SecureRandom.uuid,
            external_customer_id: customer.external_id,
          }
        end

        before do
          create(:active_subscription, customer: customer, organization: organization)
        end

        it 'returns a not found error' do
          validate_event

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::NotFoundFailure)
            expect(result.error.message).to eq('subscription_not_found')
          end
        end

        it 'enqueues a SendWebhookJob' do
          expect { validate_event }.to have_enqueued_job(SendWebhookJob)
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

      context 'when code does not exist' do
        let(:params) do
          { external_customer_id: customer.external_id, code: 'event_code' }
        end

        it 'returns an event_not_found error' do
          validate_event

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::NotFoundFailure)
            expect(result.error.message).to eq('billable_metric_not_found')
          end
        end

        it 'enqueues a SendWebhookJob' do
          expect { validate_event }.to have_enqueued_job(SendWebhookJob)
        end
      end

      context 'when event belongs to a recurring persisted event' do
        let(:billable_metric) do
          create(
            :billable_metric,
            organization: organization,
            aggregation_type: 'recurring_count_agg',
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

          it 'enqueues a SendWebhookJob' do
            expect { validate_event }.to have_enqueued_job(SendWebhookJob)
          end
        end
      end

      context 'when event belongs to a recurring persisted event and subscription is terminated' do
        let(:billable_metric) do
          create(
            :billable_metric,
            organization:,
            aggregation_type: 'recurring_count_agg',
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

        it 'enqueues a SendWebhookJob' do
          expect { validate_event }.to have_enqueued_job(SendWebhookJob)
        end
      end

      context 'when customer is not given' do
        let(:params) do
          { code: billable_metric.code, external_subscription_ids: [SecureRandom.uuid] }
        end

        let(:validate_event) do
          described_class.call(
            organization: organization,
            params: params,
            result: result,
            customer: nil,
            batch: batch,
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

        it 'enqueues a SendWebhookJob' do
          expect { validate_event }.to have_enqueued_job(SendWebhookJob)
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
          create(:active_subscription, customer: customer, organization: organization)
        end

        it 'returns subscription is invalid error' do
          validate_event

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::NotFoundFailure)
            expect(result.error.message).to eq('subscription_not_found')
          end
        end

        it 'enqueues a SendWebhookJob' do
          expect { validate_event }.to have_enqueued_job(SendWebhookJob)
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

        it 'enqueues a SendWebhookJob' do
          expect { validate_event }.to have_enqueued_job(SendWebhookJob)
        end
      end

      context 'when event belongs to a recurring persisted metric' do
        let(:billable_metric) do
          create(
            :billable_metric,
            organization: organization,
            aggregation_type: 'recurring_count_agg',
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

          it 'enqueues a SendWebhookJob' do
            expect { validate_event }.to have_enqueued_job(SendWebhookJob)
          end
        end
      end
    end
  end
end
