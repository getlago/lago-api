# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Events::ValidateCreationService, type: :service do
  subject(:validate_event) do
    described_class.call(
      organization: organization,
      params: params,
      result: result,
      customer: customer,
      batch: batch
    )
  end

  let(:organization) { create(:organization) }
  let(:result) { BaseService::Result.new }
  let(:customer) { create(:customer, organization: organization) }
  let(:billable_metric) { create(:billable_metric, organization: organization) }
  let(:params) do
    { customer_id: customer.customer_id, code: billable_metric.code }
  end

  describe '.call' do
    let!(:subscription) { create(:active_subscription, customer: customer, organization: organization) }

    context "when batch is false" do
      let(:batch) { false }

      context 'when customer has only one active subscription and subscription_id is not given' do
        it 'does not return any validation errors' do
          expect(validate_event).to be_nil
          expect(result).to be_success
        end
      end

      context 'when customer has only one active subscription and customer is not given' do
        let(:params) do
          { code: billable_metric.code, subscription_id: subscription.id }
        end

        it 'does not return any validation errors' do
          expect(validate_event).to be_nil
          expect(result).to be_success
        end
      end

      context 'when customer has two active subscriptions' do
        before { create(:active_subscription, customer: customer, organization: organization) }

        let(:params) do
          { code: billable_metric.code, subscription_id: subscription.id }
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
            customer: nil
          )
        end

        it 'returns customer cannot be found error' do
          validate_event

          expect(result).not_to be_success
          expect(result.error).to eq('customer cannot be found')
        end

        it 'enqueues a SendWebhookJob' do
          expect { validate_event }.to have_enqueued_job(SendWebhookJob)
        end
      end

      context 'when there are two active subscriptions but subscription_id is not given' do
        before do
          create(:active_subscription, customer: customer, organization: organization)
        end

        it 'returns subscription is not given error' do
          validate_event

          expect(result).not_to be_success
          expect(result.error).to eq('subscription does not exist or is not given')
        end

        it 'enqueues a SendWebhookJob' do
          expect { validate_event }.to have_enqueued_job(SendWebhookJob)
        end
      end

      context 'when there are two active subscriptions but subscription_id is invalid' do
        let(:params) do
          {
            code: billable_metric.code,
            subscription_id: SecureRandom.uuid,
            customer_id: customer.customer_id
          }
        end

        before do
          create(:active_subscription, customer: customer, organization: organization)
        end

        it 'returns subscription is invalid error' do
          validate_event

          expect(result).not_to be_success
          expect(result.error).to eq('subscription_id is invalid')
        end

        it 'enqueues a SendWebhookJob' do
          expect { validate_event }.to have_enqueued_job(SendWebhookJob)
        end
      end

      context 'when code does not exist' do
        let(:params) do
          { customer_id: customer.customer_id, code: 'event_code' }
        end

        it 'returns code does not exist error' do
          validate_event

          expect(result).not_to be_success
          expect(result.error).to eq('code does not exist')
        end

        it 'enqueues a SendWebhookJob' do
          expect { validate_event }.to have_enqueued_job(SendWebhookJob)
        end
      end
    end

    context "when batch is true" do
      let(:batch) { true }

      context 'when everything is passing' do
        let(:params) do
          { subscription_ids: [subscription.id], code: billable_metric.code }
        end

        it 'does not return any validation errors' do
          expect(validate_event).to be_nil
          expect(result).to be_success
        end
      end

      context 'when subscription_ids is blank' do
        let(:params) do
          { subscription_ids: [] }
        end

        it 'returns subscription is not given error' do
          validate_event

          expect(result).not_to be_success
          expect(result.error).to eq('subscription does not exist or is not given')
        end

        it 'enqueues a SendWebhookJob' do
          expect { validate_event }.to have_enqueued_job(SendWebhookJob)
        end
      end

      context 'when customer is not given' do
        let(:params) do
          { code: billable_metric.code, subscription_ids: [SecureRandom.uuid] }
        end

        let(:validate_event) do
          described_class.call(
            organization: organization,
            params: params,
            result: result,
            customer: nil,
            batch: batch
          )
        end

        it 'returns customer cannot be found error' do
          validate_event

          expect(result).not_to be_success
          expect(result.error).to eq('customer cannot be found')
        end

        it 'enqueues a SendWebhookJob' do
          expect { validate_event }.to have_enqueued_job(SendWebhookJob)
        end
      end

      context 'when there are two active subscriptions but subscription_ids is invalid' do
        let(:params) do
          {
            code: billable_metric.code,
            subscription_ids: [SecureRandom.uuid],
            customer_id: customer.customer_id
          }
        end

        before do
          create(:active_subscription, customer: customer, organization: organization)
        end

        it 'returns subscription is invalid error' do
          validate_event

          expect(result).not_to be_success
          expect(result.error).to eq('subscription_id is invalid')
        end

        it 'enqueues a SendWebhookJob' do
          expect { validate_event }.to have_enqueued_job(SendWebhookJob)
        end
      end

      context 'when code does not exist' do
        let(:params) do
          {
            code: 'event_code',
            subscription_ids: [subscription.id],
            customer_id: customer.customer_id
          }
        end

        it 'returns code does not exist error' do
          validate_event

          expect(result).not_to be_success
          expect(result.error).to eq('code does not exist')
        end

        it 'enqueues a SendWebhookJob' do
          expect { validate_event }.to have_enqueued_job(SendWebhookJob)
        end
      end
    end
  end
end
