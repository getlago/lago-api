# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::UpdateAlertService do
  subject(:result) { described_class.call(alert:, params:, billable_metric:) }

  let(:alert) { create(:alert, thresholds: [1, 50]) }
  let(:billable_metric) { nil }

  describe "#call" do
    context "when update is successful" do
      let(:params) do
        {code: "new_code", thresholds: [
          {code: :warn, value: 100},
          {code: :critical, value: 200}
        ]}
      end

      it "assigns the alert to the result" do
        expect(result).to be_success
        expect(result.alert).to eq(alert)
        expect(alert.reload.code).to eq("new_code")
        expect(alert.reload.thresholds.map(&:value)).to eq [100, 200]
        expect(alert.reload.thresholds.map(&:code)).to eq ["warn", "critical"]
      end
    end
  end
end
