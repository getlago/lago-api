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
  let(:external_subscription_id) { subscription.external_id }
  let(:code) { billable_metric&.code }
  let(:timestamp) { Time.current - 1.second }
  let(:event_properties) { {} }

  let(:event) do
    create(
      :event,
      organization_id: organization.id,
      external_subscription_id:,
      timestamp:,
      code:,
      properties: event_properties
    )
  end

  describe '#call' do
    it 'assigns the customer external_id' do
      result = process_service.call

      aggregate_failures do
        expect(result).to be_success
        expect(event.external_customer_id).to eq(customer.external_id)
      end
    end

    it 'flags the lifetime usage for refresh' do
      create(:usage_threshold, plan:)

      process_service.call

      expect(subscription.reload.lifetime_usage).to be_present
      expect(subscription.lifetime_usage.recalculate_current_usage).to be(true)
    end

    it 'flags wallets for refresh' do
      wallet = create(:wallet, customer:)

      expect { process_service.call }.to change { wallet.reload.ready_to_be_refreshed }.from(false).to(true)
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

    context 'when there is an error' do
      it 'delivers an error webhook' do
        allow(event).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(event))

        expect { process_service.call }.to have_enqueued_job(SendWebhookJob)
      end
    end
  end
end
