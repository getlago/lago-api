# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::PostProcessService do
  subject(:process_service) { described_class.new(event:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:, started_at:) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:charge) { create(:standard_charge, :pay_in_advance, plan:, billable_metric:) }

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

  before do
    charge
    create(:wallet, customer:)
  end

  describe "#call" do
    it "marks customer as awaiting wallet refresh" do
      expect { process_service.call }.to change { customer.reload.awaiting_wallet_refresh }.from(false).to(true)
    end

    it "tracks subscription activity" do
      allow(UsageMonitoring::TrackSubscriptionActivityService).to receive(:call)

      process_service.call

      expect(UsageMonitoring::TrackSubscriptionActivityService).to have_received(:call)
        .with(subscription:, organization:)
    end

    context "with events enrichment" do
      it "does not create an enriched event" do
        expect { process_service.call }.not_to change(EnrichedEvent, :count)
      end

      context "when the feature flag is enabled" do
        let(:organization) { create(:organization, feature_flags: [:postgres_enriched_events]) }

        it "creates enriched event" do
          expect { process_service.call }.to change(EnrichedEvent, :count).by(1)
        end
      end
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
