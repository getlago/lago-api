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
      properties: event_properties,
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

    context 'when event code matches a unique count billable metric' do
      let(:billable_metric) do
        create(:billable_metric, organization:, aggregation_type: 'unique_count_agg', field_name: 'item_id')
      end

      let(:event_properties) do
        {
          billable_metric.field_name => 'ext_12345',
          'operation_type' => 'add',
        }
      end

      it 'creates a quantified event' do
        result = nil

        aggregate_failures do
          expect { result = process_service.call }
            .to change(QuantifiedEvent, :count).by(1)

          expect(result).to be_success
        end
      end
    end

    context 'when event matches an pay_in_advance charge that is not invoiceable' do
      let(:charge) { create(:standard_charge, :pay_in_advance, plan:, billable_metric:, invoiceable: false) }
      let(:billable_metric) do
        create(:billable_metric, organization:, aggregation_type: 'sum_agg', field_name: 'item_id')
      end

      let(:event_properties) { { billable_metric.field_name => '12' } }

      before { charge }

      it 'enqueues a job to perform the pay_in_advance aggregation' do
        expect { process_service.call }.to have_enqueued_job(Fees::CreatePayInAdvanceJob)
      end

      context 'when charge is invoiceable' do
        before { charge.update!(invoiceable: true) }

        it 'does not enqueue a job to perform the pay_in_advance aggregation' do
          expect { process_service.call }.not_to have_enqueued_job(Fees::CreatePayInAdvanceJob)
        end
      end

      context 'when multiple charges have the billable metric' do
        before { create(:standard_charge, :pay_in_advance, plan:, billable_metric:, invoiceable: false) }

        it 'enqueues a job for each charge' do
          expect { process_service.call }.to have_enqueued_job(Fees::CreatePayInAdvanceJob).twice
        end
      end
    end

    context 'when event matches a pay_in_advance charge that is invoiceable' do
      let(:charge) { create(:standard_charge, :pay_in_advance, plan:, billable_metric:, invoiceable: true) }
      let(:billable_metric) do
        create(:billable_metric, organization:, aggregation_type: 'sum_agg', field_name: 'item_id')
      end

      let(:event_properties) { { billable_metric.field_name => '12' } }

      before { charge }

      it 'enqueues a job to create the pay_in_advance charge invoice' do
        expect { process_service.call }.to have_enqueued_job(Invoices::CreatePayInAdvanceChargeJob)
      end

      context 'when charge is not invoiceable' do
        before { charge.update!(invoiceable: false) }

        it 'does not enqueue a job to create the pay_in_advance charge invoice' do
          expect { process_service.call }
            .not_to have_enqueued_job(Invoices::CreatePayInAdvanceChargeJob)
        end
      end

      context 'when multiple charges have the billable metric' do
        before { create(:standard_charge, :pay_in_advance, plan:, billable_metric:, invoiceable: true) }

        it 'enqueues a job for each charge' do
          expect { process_service.call }
            .to have_enqueued_job(Invoices::CreatePayInAdvanceChargeJob).twice
        end
      end

      context 'when value for sum_agg is negative' do
        let(:event_properties) { { billable_metric.field_name => '-5' } }

        it 'enqueues a job' do
          expect { process_service.call }
            .to have_enqueued_job(Invoices::CreatePayInAdvanceChargeJob)
        end
      end

      context 'when event field name does not batch the BM one' do
        let(:event_properties) { { 'wrong_field_name' => '-5' } }

        it 'does not enqueue a job' do
          expect { process_service.call }
            .not_to have_enqueued_job(Invoices::CreatePayInAdvanceChargeJob)
        end
      end
    end
  end
end
