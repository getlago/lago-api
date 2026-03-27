# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateSchedules::OrganizationBillingService do
  subject(:billing_service) { described_class.new(organization:, billing_at:) }

  let(:organization) { create(:organization) }
  let(:billing_at) { Time.current }

  describe "#call" do
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, organization:, customer:) }

    context "when subscription_rate_schedule is billable" do
      let!(:srs) do
        create(:subscription_rate_schedule,
          organization:,
          subscription:,
          status: :active,
          next_billing_date: billing_at.to_date,
          intervals_billed: 0,
          intervals_to_bill: nil)
      end

      it "enqueues a BillRateSchedulesJob" do
        billing_service.call

        expect(BillRateSchedulesJob).to have_been_enqueued.with([srs.id], billing_at.to_i)
      end
    end

    context "when intervals_to_bill is reached" do
      before do
        create(:subscription_rate_schedule,
          organization:,
          subscription:,
          status: :active,
          next_billing_date: billing_at.to_date,
          intervals_billed: 6,
          intervals_to_bill: 6)
      end

      it "does not enqueue a BillRateSchedulesJob" do
        billing_service.call

        expect(BillRateSchedulesJob).not_to have_been_enqueued
      end
    end

    context "when intervals_to_bill is not yet reached" do
      let!(:srs) do
        create(:subscription_rate_schedule,
          organization:,
          subscription:,
          status: :active,
          next_billing_date: billing_at.to_date,
          intervals_billed: 5,
          intervals_to_bill: 6)
      end

      it "enqueues a BillRateSchedulesJob" do
        billing_service.call

        expect(BillRateSchedulesJob).to have_been_enqueued.with([srs.id], billing_at.to_i)
      end
    end

    context "when next_billing_date is in the future" do
      before do
        create(:subscription_rate_schedule,
          organization:,
          subscription:,
          status: :active,
          next_billing_date: billing_at.to_date + 1.day,
          intervals_billed: 0)
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
          status: :terminated,
          next_billing_date: billing_at.to_date,
          intervals_billed: 0)
      end

      it "does not enqueue a BillRateSchedulesJob" do
        billing_service.call

        expect(BillRateSchedulesJob).not_to have_been_enqueued
      end
    end
  end
end
