# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clock::RateSchedulesBillerJob do
  subject { described_class }

  describe ".perform" do
    context "when there are no organizations" do
      it "does not enqueue any billing job" do
        expect do
          described_class.perform_now
        end.not_to have_enqueued_job(RateSchedules::OrganizationBillingJob)
      end
    end

    context "when there are organizations" do
      let(:organization1) { create(:organization, api_keys: []) }
      let(:organization2) { create(:organization, api_keys: []) }

      before do
        organization1
        organization2
      end

      it "enqueues RateSchedules::OrganizationBillingJob for each organization" do
        expect do
          described_class.perform_now
        end.to have_enqueued_job(RateSchedules::OrganizationBillingJob).exactly(2).times
      end

      it "passes the organization as a positional argument" do
        expect do
          described_class.perform_now
        end.to have_enqueued_job(RateSchedules::OrganizationBillingJob)
          .with(organization1)
          .and have_enqueued_job(RateSchedules::OrganizationBillingJob)
          .with(organization2)
      end
    end
  end
end
