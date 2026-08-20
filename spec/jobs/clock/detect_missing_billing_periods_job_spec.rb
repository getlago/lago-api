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

  # The sweep only reports and heals, so one organization failing must not cost the report of the
  # organizations after it.
  context "when the detection raises for an organization" do
    let(:other_organization) { create(:organization) }

    before do
      other_organization

      allow(Subscriptions::BillingPeriods::DetectMissingService).to receive(:call!)
        .with(organization: Organization.order(:id).first).and_raise("boom")
      allow(Sentry).to receive(:capture_exception)
    end

    it "reports it and carries on" do
      expect { perform }.not_to raise_error

      expect(Subscriptions::BillingPeriods::DetectMissingService).to have_received(:call!)
        .with(organization: Organization.order(:id).last)
      expect(Sentry).to have_received(:capture_exception)
    end
  end
end
