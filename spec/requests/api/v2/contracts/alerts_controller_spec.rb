# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::Contracts::AlertsController do
  let(:organization) { create(:organization, feature_flags: %w[product_catalog contract_alerts]) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, organization:, customer:, external_id: "ctr_123") }
  let(:product) { create(:product, organization:, code: "llm_tokens") }
  let(:product_filter) { create(:product_filter, organization:, product:, code: "opus") }
  let(:alert) do
    create(
      :contract_usage_units_alert,
      organization:,
      contract_external_id: contract.external_id,
      code: "opus_tokens",
      name: "Opus tokens",
      product:,
      product_filter:,
      thresholds: [1_000_000]
    )
  end

  def alert_json(alert, thresholds:)
    {
      lago_id: alert.id,
      external_contract_id: "ctr_123",
      code: alert.code,
      name: alert.name,
      alert_type: alert.alert_type,
      applies_to: {type: "contract"},
      product_code: alert.product&.code,
      product_filter_code: alert.product_filter&.code,
      with_product_filters: alert.with_product_filters,
      direction: "increasing",
      thresholds:,
      previous_value: "0.0",
      last_processed_at: nil,
      created_at: alert.created_at.iso8601(6),
      updated_at: alert.updated_at.iso8601(6),
      deleted_at: alert.deleted_at&.iso8601(6)
    }
  end

  describe "POST /api/v2/contracts/:external_id/alerts", :premium do
    subject { post_with_token(organization, "/api/v2/contracts/#{external_id}/alerts", {alert: create_params}) }

    let(:external_id) { contract.external_id }
    let(:create_params) do
      {
        code: "opus_tokens",
        name: "Opus tokens",
        alert_type: "usage_units",
        product_code: "llm_tokens",
        product_filter_code: "opus",
        thresholds: [
          {code: "warn", value: "1000000"},
          {code: "high", value: "2000000", notify_on: %w[triggered resolved]},
          {code: "every_500k", value: "500000", recurring: true}
        ]
      }
    end

    before do
      [nil, product_filter].each do |filter|
        rate_card = create(:rate_card, organization:, product:, product_filter: filter)
        create(:contract_rate_card, organization:, contract:, rate_card:)
      end
    end

    include_examples "requires API permission", "alert", "write"

    it "creates the alert and renders it" do
      subject

      expect(response).to have_http_status(:ok)
      alert = organization.contract_alerts.sole
      expect(json).to eq(
        alert: alert_json(alert, thresholds: [
          {code: "warn", value: "1000000.0", recurring: false, notify_on: %w[triggered]},
          {code: "high", value: "2000000.0", recurring: false, notify_on: %w[triggered resolved]},
          {code: "every_500k", value: "500000.0", recurring: true, notify_on: %w[triggered]}
        ])
      )
    end

    context "with a pending contract only" do
      let(:contract) { create(:contract, :pending, organization:, customer:, external_id: "ctr_123") }

      it "creates the alert" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:alert][:external_contract_id]).to eq("ctr_123")
      end
    end

    context "when the contracts with the external id have ended" do
      let(:contract) { create(:contract, :terminated, organization:, customer:, external_id: "ctr_123") }

      it "returns a forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json).to eq(code: "contract_not_live", details: [])
        expect(organization.contract_alerts).to be_empty
      end
    end

    context "without a premium license" do
      before { allow(License).to receive(:premium?).and_return(false) }

      it "returns a forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json).to eq(code: "feature_unavailable", details: [])
      end
    end

    context "without the contract_alerts flag" do
      let(:organization) { create(:organization, feature_flags: %w[product_catalog]) }

      it "returns a forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json).to eq(code: "feature_unavailable", details: [])
      end
    end

    context "when no contract has the external id" do
      let(:external_id) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("contract")
      end
    end

    context "when the product is not priced on the contract" do
      before { create(:product, organization:, code: "video_minutes") }

      let(:create_params) { super().merge(product_code: "video_minutes", product_filter_code: nil) }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("product")
      end
    end

    context "with with_product_filters on the product" do
      let(:create_params) { super().except(:product_filter_code).merge(with_product_filters: true) }

      it "creates the alert on the product and its filters" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:alert]).to include(product_code: "llm_tokens", product_filter_code: nil, with_product_filters: true)
      end
    end

    context "with a with_product_filters that is not a boolean" do
      let(:create_params) { super().except(:product_filter_code).merge(with_product_filters: "no") }

      it "returns a validation error on with_product_filters" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(
          code: "validation_errors",
          details: [{code: "value_is_invalid", field: "with_product_filters", meta: {}}]
        )
      end
    end

    context "with with_product_filters on a product filter" do
      let(:create_params) { super().merge(with_product_filters: true) }

      it "returns a validation error on with_product_filters" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(
          code: "validation_errors",
          details: [{code: "value_is_invalid", field: "with_product_filters", meta: {}}]
        )
      end
    end

    context "with a units alert without a product" do
      let(:create_params) { super().except(:product_code, :product_filter_code) }

      it "returns a validation error on the product code" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(
          code: "validation_errors",
          details: [{code: "product_required_for_units", field: "product_code", meta: {}}]
        )
      end
    end

    context "with too many thresholds" do
      let(:create_params) { super().merge(thresholds: Array.new(21) { {value: it + 1} }) }

      it "returns a validation error on the thresholds" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(
          code: "validation_errors",
          details: [{code: "too_many_thresholds", field: "thresholds", meta: {max_items: 20}}]
        )
      end
    end

    context "with a plain notify_on" do
      let(:create_params) { super().merge(thresholds: [{code: "warn", value: 10, notify_on: "resolved"}]) }

      it "returns a validation error on its notify_on rather than ignoring it" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: "thresholds[0].notify_on", meta: {}}])
      end
    end

    context "with a value that is not a number in the second threshold" do
      let(:create_params) { super().merge(thresholds: [{value: 10}, {value: "abc"}]) }

      it "returns a validation error on that threshold's value" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: "thresholds[1].value", meta: {}}])
      end
    end

    context "when the code is taken on the contract" do
      before { alert }

      let(:create_params) { super().merge(alert_type: "usage_amount", product_code: nil, product_filter_code: nil) }

      it "returns a validation error on the code" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_already_exist", field: "code", meta: {}}])
      end
    end

    context "when the type and scope already have an alert" do
      before { alert }

      let(:create_params) { super().merge(code: "other_code") }

      it "returns a validation error on the request" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "alert_already_exists", field: "base", meta: {}}])
      end
    end

    context "without the alert parameter" do
      subject { post_with_token(organization, "/api/v2/contracts/#{external_id}/alerts", {}) }

      it "returns a bad request error" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("missing_parameter")
      end
    end
  end

  describe "PUT /api/v2/contracts/:external_id/alerts/:code" do
    subject do
      put_with_token(organization, "/api/v2/contracts/#{external_id}/alerts/#{code}", {alert: update_params})
    end

    let(:external_id) { contract.external_id }
    let(:code) { alert.code }
    let(:update_params) do
      {name: "Opus spend", thresholds: [{code: "high", value: "2000000", notify_on: %w[triggered resolved]}]}
    end

    include_examples "requires API permission", "alert", "write"

    it "updates the name and replaces the thresholds" do
      subject

      expect(response).to have_http_status(:ok)
      expect(json).to eq(
        alert: alert_json(alert.reload, thresholds: [
          {code: "high", value: "2000000.0", recurring: false, notify_on: %w[triggered resolved]}
        ])
      )
      expect(alert.name).to eq("Opus spend")
    end

    context "with the code, the type and the scope" do
      let(:update_params) do
        {
          name: "Opus spend",
          code: "new_code",
          alert_type: "usage_amount",
          product_code: "llm_tokens",
          product_filter_code: "opus",
          with_product_filters: true
        }
      end

      it "returns a validation error on each of them and changes nothing" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(
          code: "validation_errors",
          details: [
            {code: "value_cannot_be_changed", field: "code", meta: {}},
            {code: "value_cannot_be_changed", field: "alert_type", meta: {}},
            {code: "value_cannot_be_changed", field: "product_code", meta: {}},
            {code: "value_cannot_be_changed", field: "product_filter_code", meta: {}},
            {code: "value_cannot_be_changed", field: "with_product_filters", meta: {}}
          ]
        )
        expect(alert.reload.name).to eq("Opus tokens")
      end
    end

    context "with invalid thresholds" do
      let(:update_params) { {thresholds: [{value: 10}, {value: "10.0"}]} }

      it "returns a validation error on the later threshold's value" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(
          code: "validation_errors",
          details: [{code: "duplicate_threshold_values", field: "thresholds[1].value", meta: {}}]
        )
      end
    end

    context "when the contract has ended" do
      let(:contract) { create(:contract, :terminated, organization:, customer:, external_id: "ctr_123") }

      it "returns a forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json).to eq(code: "contract_not_live", details: [])
      end
    end

    context "when the alert does not exist" do
      let(:code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("alert")
      end
    end

    context "when no contract has the external id" do
      let(:external_id) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("contract")
      end
    end
  end

  describe "GET /api/v2/contracts/:external_id/alerts/:code" do
    subject { get_with_token(organization, "/api/v2/contracts/#{external_id}/alerts/#{code}") }

    let(:external_id) { contract.external_id }
    let(:code) { alert.code }

    include_examples "requires API permission", "alert", "read"

    it "returns the alert" do
      subject

      expect(response).to have_http_status(:ok)
      expect(json).to eq(
        alert: alert_json(alert, thresholds: [
          {code: "warn1000000", value: "1000000.0", recurring: false, notify_on: %w[triggered]}
        ])
      )
    end

    context "when the contract has ended" do
      let(:contract) { create(:contract, :terminated, organization:, customer:, external_id: "ctr_123") }

      it "returns the alert" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:alert][:lago_id]).to eq(alert.id)
      end
    end

    context "when the alert is on another contract" do
      let(:code) { create(:contract_alert, organization:).code }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("alert")
      end
    end

    context "when the alert is deleted" do
      before { alert.discard! }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("alert")
      end
    end

    context "when no contract has the external id" do
      let(:external_id) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("contract")
      end
    end
  end

  describe "GET /api/v2/contracts/:external_id/alerts" do
    subject { get_with_token(organization, "/api/v2/contracts/#{external_id}/alerts") }

    let(:external_id) { contract.external_id }
    let(:amount_alert) do
      create(:contract_usage_amount_alert, organization:, contract_external_id: contract.external_id, thresholds: [5_000_00])
    end

    before do
      alert
      amount_alert
      create(:contract_alert, organization:)
      create(:contract_alert, contract_external_id: contract.external_id)
    end

    include_examples "requires API permission", "alert", "read"

    it "returns the alerts on the contract, newest first", :bullet do
      subject

      expect(response).to have_http_status(:ok)
      expect(json).to eq(
        alerts: [
          alert_json(amount_alert, thresholds: [
            {code: "warn500000", value: "500000.0", recurring: false, notify_on: %w[triggered]}
          ]),
          alert_json(alert, thresholds: [
            {code: "warn1000000", value: "1000000.0", recurring: false, notify_on: %w[triggered]}
          ])
        ],
        meta: {next_cursor: nil, prev_cursor: nil}
      )
    end

    context "when the contract has ended" do
      let(:contract) { create(:contract, :terminated, organization:, customer:, external_id: "ctr_123") }

      it "returns its alerts" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:alerts].map { it[:lago_id] }).to eq([amount_alert.id, alert.id])
      end
    end

    context "when no contract has the external id" do
      let(:external_id) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("contract")
      end
    end

    it_behaves_like "a cursor paginated v2 endpoint", collection: :alerts, model: UsageMonitoring::ContractAlert do
      let(:paginated_path) { "/api/v2/contracts/#{contract.external_id}/alerts" }
      let(:create_paginated_record) do
        ->(created_at) { create(:contract_usage_units_alert, organization:, contract_external_id: contract.external_id, created_at:) }
      end
    end

    it_behaves_like "a v2 list filtered on created_at", collection: :alerts do
      let(:filtered_path) { "/api/v2/contracts/#{contract.external_id}/alerts" }
      let(:create_filtered_record) do
        ->(created_at) { create(:contract_usage_units_alert, organization:, contract_external_id: contract.external_id, created_at:) }
      end
    end
  end

  describe "DELETE /api/v2/contracts/:external_id/alerts/:code" do
    subject { delete_with_token(organization, "/api/v2/contracts/#{external_id}/alerts/#{code}") }

    let(:external_id) { contract.external_id }
    let(:code) { alert.code }
    let(:triggered_alert) { create(:contract_triggered_alert, alert:, contract:) }

    before { triggered_alert }

    include_examples "requires API permission", "alert", "write"

    it "deletes the alert and keeps its history" do
      subject

      expect(response).to have_http_status(:ok)
      expect(alert.reload).to be_discarded
      expect(json).to eq(alert: alert_json(alert, thresholds: []))
      expect(alert.thresholds).to be_empty
      expect(triggered_alert.reload).to be_present
    end

    context "when the contract has ended" do
      let(:contract) { create(:contract, :terminated, organization:, customer:, external_id: "ctr_123") }

      it "deletes the alert" do
        subject

        expect(response).to have_http_status(:ok)
        expect(alert.reload).to be_discarded
      end
    end

    context "when the alert does not exist" do
      let(:code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("alert")
      end
    end

    context "when no contract has the external id" do
      let(:external_id) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("contract")
      end
    end
  end
end
