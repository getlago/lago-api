# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::PostProcessService do
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

  describe "#call" do
    it "flags wallets for refresh" do
      wallet = create(:wallet, customer:)

      expect { process_service.call }.to change { wallet.reload.ready_to_be_refreshed }.from(false).to(true)
    end

    it "tracks subscription activity" do
      allow(UsageMonitoring::TrackSubscriptionActivityService).to receive(:call)

      process_service.call

      expect(UsageMonitoring::TrackSubscriptionActivityService).to have_received(:call)
        .with(subscription:, organization:)
    end

    context "when event matches an pay_in_advance charge" do
      let(:charge) { create(:standard_charge, :pay_in_advance, plan:, billable_metric:, invoiceable: false) }
      let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "sum_agg", field_name: "item_id") }
      let(:event_properties) { {billable_metric.field_name => "12"} }

      before { charge }

      it "enqueues a job to perform the pay_in_advance aggregation" do
        expect { process_service.call }.to have_enqueued_job(Events::PayInAdvanceJob)
      end
    end
  end
end
