# frozen_string_literal: true

require "rails_helper"

describe BillingSegments::ScheduleJob, job: true do
  subject { described_class }

  let(:customer) { create(:customer) }

  it_behaves_like "a unique job" do
    let(:job_args) { [customer.id] }
  end

  describe ".perform" do
    it "schedules the customer's due segments" do
      allow(BillingSegments::ScheduleService).to receive(:call!).and_call_original

      described_class.perform_now(customer.id)

      expect(BillingSegments::ScheduleService).to have_received(:call!).with(customer:)
    end
  end
end
