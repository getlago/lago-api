# frozen_string_literal: true

require "rails_helper"

RSpec.describe EventDestinations::CustomerFullUsage::RefreshedService do
  subject(:service) { described_class.new(object: customer) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, code: "enterprise_monthly") }
  let(:subscription) { create(:subscription, customer:, plan:, started_at: 6.months.ago) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let!(:charge) { create(:standard_charge, plan:, billable_metric:, organization:) }
  let(:producer) { instance_double(Lago::Kinesis::Producer, produce: nil) }
  let(:producer_calls) { [] }

  before do
    subscription
    allow(Lago::Kinesis::Producer).to receive(:new).and_return(producer)
    allow(producer).to receive(:produce) { |args| producer_calls << args }
  end

  context "when the organization has no destination" do
    it "delivers nothing" do
      expect(service.call).to be_success
      expect(producer_calls).to be_empty
    end
  end

  # full_usage is refused unless the organization has granular_lifetime_usage and a premium
  # license, so without this every delivery is silently skipped.
  context "when the organization has a destination", :premium do
    before do
      organization.update!(premium_integrations: ["granular_lifetime_usage"])
      create(:kinesis_destination, organization:)
    end

    it "asks for usage since the subscription started, in one call carrying every charge id" do
      allow(Invoices::CustomerUsageService).to receive(:call).and_call_original

      service.call

      expect(Invoices::CustomerUsageService).to have_received(:call).once.with(
        hash_including(
          usage_filters: an_object_having_attributes(
            full_usage: true,
            filter_by_charge_id: [charge.id]
          )
        )
      )
      expect(producer_calls.size).to eq(1)
    end

    it "delivers a snapshot whose window starts at subscription.started_at" do
      service.call

      usage = producer_calls.first[:data][:customer_usage]
      expect(Time.zone.parse(usage[:from_datetime])).to be_within(1.second).of(subscription.started_at)
    end

    it "carries the full usage event type and the shared object type" do
      service.call

      expect(producer_calls.first[:data]).to include(
        event_type: "customer_full_usage.refreshed.v1",
        object_type: "customer_usage"
      )
    end

    context "when the plan is on the exclusion list" do
      before do
        destination = StreamingDestinations::BaseDestination.for_event(organization, described_class::EVENT_TYPE).first
        destination.customer_full_usage_excluded_plan_codes = ["enterprise_monthly"]
        destination.save!
      end

      it "delivers nothing for that subscription" do
        expect(service.call).to be_success
        expect(producer_calls).to be_empty
      end
    end

    context "when the plan carries a prorated charge" do
      before do
        recurring_metric = create(:billable_metric, organization:, recurring: true, aggregation_type: "sum_agg", field_name: "amount")
        create(:standard_charge, plan:, billable_metric: recurring_metric, organization:, prorated: true)
        allow(Rails.logger).to receive(:warn)
      end

      it "skips rather than raising, so the current period record is unaffected" do
        expect(service.call).to be_success
        expect(producer_calls).to be_empty
        expect(Rails.logger).to have_received(:warn).with(a_string_matching(/skipped for subscription/))
      end
    end
  end
end
