# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::UsageSnapshot do
  describe ".measure" do
    subject(:snapshot) do
      described_class.measure do
        travel 2.seconds
        usage
      end
    end

    let(:usage) { instance_double(SubscriptionUsage) }

    before { freeze_time }

    it "dates the usage with the time read before it is built" do
      measured_at = Time.current

      expect(snapshot).to have_attributes(usage:, measured_at:)
    end
  end
end
