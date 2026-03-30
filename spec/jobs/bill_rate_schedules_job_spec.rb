# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillRateSchedulesJob do
  subject { described_class }

  describe ".perform" do
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }
    let(:plan) { create(:plan, organization:) }
    let(:subscription) { create(:subscription, customer:, plan:, organization:) }
    let(:product_item) { create(:product_item, organization:) }
    let(:rate_schedule) { create(:rate_schedule, organization:) }
    let(:subscription_rate_schedule) do
      create(:subscription_rate_schedule, organization:, subscription:, product_item:, rate_schedule:)
    end

    let(:timestamp) { Time.current.to_i }
    let(:result) { BaseService::Result.new }

    it "calls the rate schedules billing service" do
      allow(Invoices::RateSchedulesBillingService).to receive(:call!)
        .and_return(result)

      described_class.perform_now([subscription_rate_schedule.id], timestamp)

      expect(Invoices::RateSchedulesBillingService).to have_received(:call!)
        .with(subscription_rate_schedules: anything, timestamp:, invoice: nil)
    end

    context "when service fails and invoice is generating" do
      let(:invoice) { create(:invoice, customer:, status: :generating) }
      let(:failed_result) do
        r = BaseService::Result.new
        r.invoice = invoice
        r.fail_with_error!(StandardError.new("test"))
        r
      end

      it "re-enqueues with the generating invoice" do
        allow(Invoices::RateSchedulesBillingService).to receive(:call!).and_return(failed_result)

        expect do
          described_class.perform_now([subscription_rate_schedule.id], timestamp)
        end.to have_enqueued_job(described_class)
          .with([subscription_rate_schedule.id], timestamp, invoice:)
      end
    end

    context "when subscription rate schedules not found" do
      it "returns early" do
        expect(Invoices::RateSchedulesBillingService).not_to receive(:call!)

        described_class.perform_now([SecureRandom.uuid], timestamp)
      end
    end
  end
end
