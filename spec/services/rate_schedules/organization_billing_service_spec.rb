# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateSchedules::OrganizationBillingService do
  subject(:billing_service) { described_class.new(organization:, billing_at:) }

  let(:organization) { create(:organization) }
  let(:billing_at) { DateTime.new(2026, 2, 2) }

  describe "#call" do
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, organization:, customer:) }

    context "when the latest cycle has ended and has no fee" do
      let(:srs) do
        create(:subscription_rate_schedule, :with_cycles,
          organization:,
          subscription:,
          status: :active,
          started_at: DateTime.new(2026, 1, 1),
          cycles_count: 1)
      end

      before { srs }

      it "enqueues a BillRateSchedulesJob grouped by customer" do
        billing_service.call

        expect(BillRateSchedulesJob).to have_been_enqueued.with([srs.id], billing_at.to_i)
      end
    end

    context "when the cycle has already been billed (fee exists)" do
      let(:srs) do
        create(:subscription_rate_schedule, :with_cycles,
          organization:,
          subscription:,
          status: :active,
          started_at: DateTime.new(2026, 1, 1),
          cycles_count: 1)
      end

      before do
        create(:fee, subscription:, subscription_rate_schedule: srs, subscription_rate_schedule_cycle: srs.cycles.first)
      end

      it "does not enqueue a BillRateSchedulesJob" do
        billing_service.call

        expect(BillRateSchedulesJob).not_to have_been_enqueued
      end
    end

    context "when the cycle has not ended yet" do
      before do
        create(:subscription_rate_schedule, :with_cycles,
          organization:,
          subscription:,
          status: :active,
          started_at: DateTime.new(2026, 2, 1),
          cycles_count: 1)
      end

      it "does not enqueue a BillRateSchedulesJob" do
        billing_service.call

        expect(BillRateSchedulesJob).not_to have_been_enqueued
      end
    end

    context "when the subscription_rate_schedule is terminated" do
      before do
        create(:subscription_rate_schedule,
          organization:,
          subscription:,
          status: :terminated,
          started_at: DateTime.new(2026, 1, 1))
      end

      it "does not enqueue a BillRateSchedulesJob" do
        billing_service.call

        expect(BillRateSchedulesJob).not_to have_been_enqueued
      end
    end

    context "when the subscription_rate_schedule has no cycles" do
      before do
        create(:subscription_rate_schedule,
          organization:,
          subscription:,
          status: :active)
      end

      it "does not enqueue a BillRateSchedulesJob" do
        billing_service.call

        expect(BillRateSchedulesJob).not_to have_been_enqueued
      end
    end

    context "with multiple customers" do
      let(:other_customer) { create(:customer, organization:) }
      let(:other_subscription) { create(:subscription, organization:, customer: other_customer) }

      before do
        create(:subscription_rate_schedule, :with_cycles,
          organization:,
          subscription:,
          status: :active,
          started_at: DateTime.new(2026, 1, 1),
          cycles_count: 1)

        create(:subscription_rate_schedule, :with_cycles,
          organization:,
          subscription: other_subscription,
          status: :active,
          started_at: DateTime.new(2026, 1, 1),
          cycles_count: 1)
      end

      it "enqueues one BillRateSchedulesJob per customer" do
        billing_service.call

        expect(BillRateSchedulesJob).to have_been_enqueued.exactly(2).times
      end
    end
  end
end
