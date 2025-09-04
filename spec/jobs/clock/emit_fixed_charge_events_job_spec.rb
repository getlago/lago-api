# frozen_string_literal: true

require "rails_helper"

describe Clock::EmitFixedChargeEventsJob, job: true do
  subject(:job) { described_class }

  describe ".perform" do
    let(:organization_1) { create(:organization) }
    let(:organization_2) { create(:organization) }

    before do
      organization_1
      organization_2
    end

    it "enqueues Subscriptions::OrganizationEmitFixedChargeEventsJob for each organization" do
      freeze_time do
        described_class.perform_now

        expect(Subscriptions::OrganizationEmitFixedChargeEventsJob)
          .to have_been_enqueued
          .with(organization: organization_1, timestamp: Time.current.to_i)
          .once

        expect(Subscriptions::OrganizationEmitFixedChargeEventsJob)
          .to have_been_enqueued
          .with(organization: organization_2, timestamp: Time.current.to_i)
          .once
      end
    end
  end
end
