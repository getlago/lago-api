# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::UsageMonitoring::AlertResolvedService do
  subject(:webhook_service) { described_class.new(object: resolved_alert) }

  let(:resolved_alert) do
    create(:triggered_alert, kind: :resolved, in_alarm_thresholds: ["warn"], fully_resolved: false)
  end

  describe ".call" do
    it_behaves_like "creates webhook", "alert.resolved", "triggered_alert"
  end
end
