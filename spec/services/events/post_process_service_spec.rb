# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Events::PostProcessService, type: :service do
  subject(:process_service) { described_class.new(event:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:, started_at:) }
  let(:billable_metric) { create(:billable_metric, organization:) }

  let(:started_at) { Time.current - 3.days }
  let(:external_customer_id) { customer.external_id }
  let(:external_subscription_id) { subscription.external_id }
  let(:code) { billable_metric&.code }
  let(:timestamp) { Time.current - 1.second }
  let(:event_properties) { {} }

  let(:event) do
    create(
      :event,
      organization_id: organization.id,
      external_customer_id:,
      external_subscription_id:,
      timestamp:,
      code:,
      properties: event_properties
    )
  end

  describe '#call' do
    context 'without external customer id' do
      let(:external_customer_id) { nil }

      it 'assigns the customer external_id' do
        result = process_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(event.external_customer_id).to eq(customer.external_id)
        end
      end

      context 'with multiple active subscription' do
        let(:second_subscription) { create(:subscription, organization:, customer:, started_at:) }

        before { second_subscription }

        it 'assigns the subscription external_id' do
          result = process_service.call

          aggregate_failures do
            expect(result).to be_success

            expect(event.external_customer_id).to eq(customer.external_id)
          end
        end
      end
    end

    context 'without external subscription id' do
      let(:external_subscription_id) { nil }

      before { subscription }

      context 'with a single customer subscription' do
        it 'assigns the subscription external_id' do
          result = process_service.call

          aggregate_failures do
            expect(result).to be_success

            expect(event.external_subscription_id).to eq(subscription.external_id)
          end
        end
      end

      context 'with multiple active subscription' do
        let(:second_subscription) { create(:subscription, organization:, customer:, started_at:) }

        before { second_subscription }

        it 'does not assigns the subscription external_id' do
          result = process_service.call

          aggregate_failures do
            expect(result).to be_success

            expect(event.external_customer_id).to eq(customer.external_id)
            expect(event.external_subscription_id).to be_nil
          end
        end
      end
    end

    context 'when event matches an pay_in_advance charge' do
      let(:charge) { create(:standard_charge, :pay_in_advance, plan:, billable_metric:, invoiceable: false) }
      let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: 'sum_agg', field_name: 'item_id') }
      let(:event_properties) { {billable_metric.field_name => '12'} }

      before { charge }

      it 'enqueues a job to perform the pay_in_advance aggregation' do
        expect { process_service.call }.to have_enqueued_job(Events::PayInAdvanceJob)
      end
    end
  end
end
