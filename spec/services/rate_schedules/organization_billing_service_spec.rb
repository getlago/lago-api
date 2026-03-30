# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateSchedules::OrganizationBillingService do
  subject(:billing_service) { described_class.new(organization:, billing_at:) }

  let(:organization) { create(:organization) }
  let(:billing_at) { Time.current }

  describe "#call" do
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, organization:, customer:) }
    let(:rate_schedule) do
      create(:rate_schedule,
        organization:,
        billing_interval_unit: :month,
        billing_interval_count: 1)
    end

    context "when first billing period has elapsed" do
      let!(:srs) do
        create(:subscription_rate_schedule,
          organization:,
          subscription:,
          rate_schedule:,
          status: :active,
          started_at: 2.months.ago)
      end

      it "enqueues a BillRateSchedulesJob" do
        billing_service.call

        expect(BillRateSchedulesJob).to have_been_enqueued.with([srs.id], billing_at.to_i)
      end
    end

    context "when first billing period has not elapsed yet" do
      let!(:srs) do
        create(:subscription_rate_schedule,
          organization:,
          subscription:,
          rate_schedule:,
          status: :active,
          started_at: 1.day.ago)
      end

      it "does not enqueue a BillRateSchedulesJob" do
        billing_service.call

        expect(BillRateSchedulesJob).not_to have_been_enqueued
      end
    end

    context "when subscription_rate_schedule is terminated" do
      before do
        create(:subscription_rate_schedule,
          organization:,
          subscription:,
          rate_schedule:,
          status: :terminated,
          started_at: 2.months.ago)
      end

      it "does not enqueue a BillRateSchedulesJob" do
        billing_service.call

        expect(BillRateSchedulesJob).not_to have_been_enqueued
      end
    end
  end
end
