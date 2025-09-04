# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::OrganizationEmitFixedChargeEventsJob, type: :job do
  let(:service) { Subscriptions::OrganizationEmitFixedChargeEventsService }
  let(:organization) { create(:organization) }
  let(:timestamp) { Time.current.to_i }

  describe ".perform" do
    before do
      allow(service).to receive(:call!)
    end

    it "calls Subscriptions::OrganizationEmitFixedChargeEventsService" do
      described_class.perform_now(organization:, timestamp:)

      expect(service)
        .to have_received(:call!)
        .with(organization:, timestamp: Time.zone.at(timestamp))
        .once
    end

    it "uses current timestamp when not provided" do
      freeze_time do
        described_class.perform_now(organization:)

        expect(service)
          .to have_received(:call!)
          .with(organization:, timestamp: Time.current)
          .once
      end
    end
  end
end
