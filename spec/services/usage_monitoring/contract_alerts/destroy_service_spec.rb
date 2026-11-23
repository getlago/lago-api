# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ContractAlerts::DestroyService do
  subject(:result) { described_class.call(alert:) }

  let_it_be(:organization) { create(:organization) }

  let(:alert) { create(:contract_alert, organization:, thresholds: [10_00, 20_00]) }
  let(:triggered_alert) { create(:contract_triggered_alert, alert:, organization:) }

  before { triggered_alert }

  it "discards the alert, deletes its thresholds and keeps its history" do
    expect(result).to be_success
    expect(result.alert).to eq(alert)
    expect(result.alert).to be_discarded
    expect(UsageMonitoring::ContractAlertThreshold.where(contract_alert_id: alert.id)).to be_empty
    expect(UsageMonitoring::ContractTriggeredAlert.where(contract_alert_id: alert.id)).to eq([triggered_alert])
  end

  context "without an alert" do
    subject(:result) { described_class.call(alert: nil) }

    it "returns a not found failure" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::NotFoundFailure)
      expect(result.error.error_code).to eq("alert_not_found")
    end
  end
end
