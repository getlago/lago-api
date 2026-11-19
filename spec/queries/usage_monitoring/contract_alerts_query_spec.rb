# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ContractAlertsQuery do
  subject(:result) { described_class.call(organization:, pagination:, filters:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:contract) { create(:contract, organization:) }
  # One alert per type and scope on a contract: each units alert gets its own product
  let_it_be(:older_alert) do
    create(:contract_usage_units_alert, organization:, contract_external_id: contract.external_id, created_at: 2.days.ago)
  end
  let_it_be(:newer_alert) do
    create(:contract_usage_units_alert, organization:, contract_external_id: contract.external_id, created_at: 1.day.ago)
  end

  let(:pagination) { nil }
  let(:filters) { {contract_external_id: contract.external_id} }

  before_all do
    create(:contract_alert, organization:)
    create(:contract_alert, organization:, contract_external_id: contract.external_id, deleted_at: Time.current)
    create(:contract_alert, contract_external_id: contract.external_id)
  end

  it "returns the kept alerts on the contract external id, newest first" do
    expect(result).to be_success
    expect(result.contract_alerts).to eq([newer_alert, older_alert])
  end

  context "without a contract external id" do
    let(:filters) { {} }

    it "returns no alert" do
      expect(result.contract_alerts).to be_empty
    end
  end

  context "with created_at filters" do
    let(:filters) { {contract_external_id: contract.external_id, created_at_from: newer_alert.created_at.iso8601(6)} }

    it "returns the alerts created in the range" do
      expect(result.contract_alerts).to eq([newer_alert])
    end
  end

  context "with an invalid created_at filter" do
    let(:filters) { {contract_external_id: contract.external_id, created_at_to: "not a date"} }

    it "fails on the filter" do
      expect(result).to be_failure
      expect(result.error.messages).to eq(created_at_to: ["invalid_date"])
    end
  end

  context "with cursor pagination" do
    let(:pagination) { CursorPagination::Cursor.new(table: "usage_monitoring_contract_alerts", limit: 1) }

    it "returns the first page" do
      page = CursorPagination::Page.new(records: result.contract_alerts, cursor: pagination)

      expect(page.records).to eq([newer_alert])
      expect(page.meta[:next_cursor]).to be_present
    end
  end
end
