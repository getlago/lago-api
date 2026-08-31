# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingSegments::BillSubscriptionService do
  describe ".call" do
    subject(:result) { described_class.call(subscription:, range:) }

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, organization:, customer:) }
    let(:range) { Time.zone.parse("2026-09-10")..Time.zone.parse("2026-09-10") }
    let(:schedule_result) { BillingSegments::ScheduleService::Result.new }
    let(:process_result) do
      BillingSegments::ProcessService::Result.new.tap do |result|
        result.invoices = []
      end
    end

    before do
      allow(BillingSegments::ScheduleService).to receive(:call).and_return(schedule_result)
      allow(BillingSegments::ProcessService).to receive(:call).and_return(process_result)
    end

    it "processes the customer after scheduling succeeds" do
      expect(result).to be_success
      expect(result.invoices).to eq([])
      expect(BillingSegments::ScheduleService).to have_received(:call).with(customer:, range:)
      expect(BillingSegments::ProcessService).to have_received(:call).with(customer:)
    end

    context "without an explicit range" do
      subject(:result) { described_class.call(subscription:) }

      it "lets the scheduler choose the default range" do
        expect(result).to be_success
        expect(BillingSegments::ScheduleService).to have_received(:call).with(customer:, range: nil)
      end
    end

    context "when scheduling fails" do
      let(:schedule_error) do
        BaseService::ValidationFailure.new(schedule_result, messages: {billing_segment: ["overlapping_periods"]})
      end

      before do
        schedule_result.fail_with_error!(schedule_error)
      end

      it "returns the schedule error without processing the customer" do
        expect(result).to be_failure
        expect(result.error).to eq(schedule_error)
        expect(BillingSegments::ProcessService).not_to have_received(:call)
      end
    end
  end
end
