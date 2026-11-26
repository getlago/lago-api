# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::ContractAlertSerializer do
  subject(:payload) { described_class.new(alert, options).serialize }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:product) { create(:product, organization:, code: "llm_tokens") }
  let_it_be(:product_filter) { create(:product_filter, organization:, product:, code: "opus") }

  let(:options) { {} }
  let(:alert) do
    create(
      :contract_usage_units_alert,
      organization:,
      contract_external_id: "ctr_123",
      code: "opus_tokens",
      name: "Opus tokens",
      product:,
      product_filter:,
      previous_value: 1_200_000,
      last_processed_at: Time.zone.parse("2026-11-05T10:00:00.123456Z"),
      created_at: Time.zone.parse("2026-11-05T09:00:00.123456Z"),
      updated_at: Time.zone.parse("2026-11-05T09:30:00.123456Z"),
      thresholds: nil
    )
  end

  before do
    create(:contract_alert_threshold, alert:, code: "every_500k", value: 500_000, recurring: true)
    create(:contract_alert_threshold, alert:, code: "high", value: 2_000_000, notify_on: %w[triggered resolved])
    create(:contract_alert_threshold, alert:, code: "warn", value: 1_000_000)
  end

  it "serializes the alert, its one-time thresholds by value, then the recurring one" do
    expect(payload).to eq(
      lago_id: alert.id,
      external_contract_id: "ctr_123",
      code: "opus_tokens",
      name: "Opus tokens",
      alert_type: "usage_units",
      scope: [{type: "contract", product_code: "llm_tokens", product_filter_codes: ["opus"]}],
      direction: "increasing",
      thresholds: [
        {code: "warn", value: BigDecimal("1000000"), recurring: false, notify_on: %w[triggered]},
        {code: "high", value: BigDecimal("2000000"), recurring: false, notify_on: %w[triggered resolved]},
        {code: "every_500k", value: BigDecimal("500000"), recurring: true, notify_on: %w[triggered]}
      ],
      previous_value: BigDecimal("1200000"),
      last_processed_at: "2026-11-05T10:00:00Z",
      created_at: "2026-11-05T09:00:00Z",
      updated_at: "2026-11-05T09:30:00Z",
      deleted_at: nil
    )
  end

  context "with microsecond timestamps" do
    let(:options) { {includes: %i[usec_timestamps]} }

    it "renders the datetimes to the microsecond" do
      expect(payload.slice(:last_processed_at, :created_at, :updated_at, :deleted_at)).to eq(
        last_processed_at: "2026-11-05T10:00:00.123456Z",
        created_at: "2026-11-05T09:00:00.123456Z",
        updated_at: "2026-11-05T09:30:00.123456Z",
        deleted_at: nil
      )
    end
  end

  context "with an alert on a product and its filters" do
    let(:alert) do
      create(:contract_usage_amount_alert, organization:, product:, with_product_filters: true, thresholds: nil)
    end

    it "renders the product and with_product_filters in the scope, as a request sends them" do
      expect(payload[:scope]).to eq([{type: "contract", product_code: "llm_tokens", with_product_filters: true}])
    end
  end

  context "with an amount alert on the whole contract" do
    let(:alert) do
      create(:contract_usage_amount_alert, organization:, contract_external_id: "ctr_123", thresholds: nil)
    end

    it "renders an empty scope" do
      expect(payload).to include(alert_type: "usage_amount", scope: [])
    end
  end

  context "when the alert is deleted" do
    before { UsageMonitoring::DestroyAlertService.call!(alert:) }

    it "renders its deletion time and no threshold" do
      expect(payload).to include(thresholds: [], deleted_at: alert.deleted_at.iso8601)
    end
  end
end
