# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clock::DetectMissingBillingPeriodsJob, job: true do
  subject(:perform) { described_class.perform_now }

  let(:organization) { create(:organization) }

  before do
    organization
    allow(Subscriptions::BillingPeriods::DetectMissingService).to receive(:call!).and_call_original
  end

  it "runs the detection for every organization" do
    perform

    expect(Subscriptions::BillingPeriods::DetectMissingService).to have_received(:call!)
      .with(organization:)
  end
end
