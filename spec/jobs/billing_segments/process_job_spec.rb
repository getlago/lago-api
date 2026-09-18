# frozen_string_literal: true

require "rails_helper"

describe BillingSegments::ProcessJob, job: true do
  subject { described_class }

  let(:customer) { create(:customer) }

  it_behaves_like "a unique job" do
    let(:job_args) { [customer.id] }
  end

  describe ".perform" do
    before { allow(BillingSegments::ProcessService).to receive(:call!).and_call_original }

    it "processes the customer's pending segments" do
      described_class.perform_now(customer.id)

      expect(BillingSegments::ProcessService).to have_received(:call!).with(customer:)
    end
  end
end
