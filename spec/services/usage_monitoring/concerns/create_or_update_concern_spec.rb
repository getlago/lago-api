# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::Concerns::CreateOrUpdateConcern do
  subject(:host) do
    Class.new(UsageMonitoring::BaseService) do
      include UsageMonitoring::Concerns::CreateOrUpdateConcern
    end.new
  end

  let_it_be(:organization) { create_default(:organization) }
  let(:alert) { create(:alert, organization:, thresholds: [], previous_value: 50) }

  before_all do
    create_default(:customer)
    create_default(:plan)
  end

  before do
    create(:alert_threshold, alert:, organization:, code: "warn", value: 10, notify_on: %w[triggered resolved])
  end

  describe "#replace_thresholds" do
    context "without an alertable, on an alert that has no previous value yet" do
      before { alert.previous_value = nil }

      it "replaces the thresholds and records no history" do
        host.replace_thresholds(alert, nil, [{code: "warn", value: 20}])

        expect(alert.thresholds.reload.map { [it.code, it.value] }).to eq([["warn", 20]])
        expect(alert.all_triggered_alerts).to be_empty
        expect(SendWebhookJob).not_to have_been_enqueued
      end
    end
  end
end
