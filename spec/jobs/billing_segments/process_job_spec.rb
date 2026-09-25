# frozen_string_literal: true

require "rails_helper"

describe BillingSegments::ProcessJob, job: true do
  subject { described_class }

  let(:customer) { create(:customer) }

  it_behaves_like "a unique job" do
    let(:job_args) { [customer.id] }
  end

  describe "unique" do
    it "releases its lock once it starts, so a request made during a run is not dropped" do
      expect(described_class.lock_strategy_class).to eq(ActiveJob::Uniqueness::Strategies::UntilExecuting)
    end
  end

  describe ".perform" do
    before { allow(BillingSegments::ProcessService).to receive(:call!).and_call_original }

    it "invoices the customer's pending segments" do
      described_class.perform_now(customer.id)

      expect(BillingSegments::ProcessService).to have_received(:call!).with(customer:)
    end
  end
end
