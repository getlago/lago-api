# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::PlanWallets::AlertsController do
  let(:organization) { create(:organization, feature_flags:) }
  let(:feature_flags) { %w[product_catalog catalog_wallets] }
  let(:catalog_plan) { create(:catalog_plan, organization:, code: "pro", currency: "USD") }
  let(:plan_wallet) { create(:plan_wallet, organization:, catalog_plan:, code: "prepaid", currency: "USD") }
  let(:alert) { create(:plan_wallet_alert, organization:, plan_wallet:, code: "low_balance", name: "Low balance") }
  let(:plan_code) { catalog_plan.code }
  let(:wallet_code) { plan_wallet.code }

  shared_examples "requires the catalog_wallets flag" do
    context "when the organization is not on catalog wallets" do
      let(:feature_flags) { %w[product_catalog] }

      it "returns a forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json).to eq(code: "feature_unavailable", details: [])
      end
    end
  end

  def create_threshold(alert, **attributes)
    create(:catalog_wallet_alert_threshold, :template, organization:, plan_wallet_alert: alert, **attributes)
  end

  def alert_json(alert, thresholds:)
    {
      lago_id: alert.id,
      lago_wallet_id: plan_wallet.id,
      wallet_code: "prepaid",
      currency: "USD",
      plan_code: "pro",
      lago_contract_id: nil,
      external_contract_id: nil,
      contract_code: nil,
      external_customer_id: nil,
      code: alert.code,
      name: alert.name,
      alert_type: alert.alert_type,
      direction: "decreasing",
      thresholds:,
      previous_value: nil,
      last_processed_at: nil,
      created_at: alert.created_at.iso8601(6),
      updated_at: alert.updated_at.iso8601(6)
    }
  end

  describe "GET /api/v2/plans/:plan_code/wallets/:wallet_code/alerts" do
    subject { get_with_token(organization, "/api/v2/plans/#{plan_code}/wallets/#{wallet_code}/alerts", query) }

    let(:query) { {} }
    let(:ongoing_alert) do
      create(:plan_wallet_alert, organization:, plan_wallet:, alert_type: "ongoing_balance", code: "low_ongoing", created_at: 1.minute.from_now)
    end

    before do
      alert
      ongoing_alert
      create(:plan_wallet_alert, organization:, plan_wallet: create(:plan_wallet, organization:, catalog_plan:))
    end

    include_examples "requires API permission", "alert", "read"
    include_examples "requires the catalog_wallets flag"

    it "returns the wallet template's alerts, newest first and unpaginated" do
      subject

      expect(response).to have_http_status(:success)
      expect(json.keys).to eq([:alerts])
      expect(json[:alerts].map { it[:code] }).to eq(%w[low_ongoing low_balance])
    end

    context "when the plan and wallet codes contain a dot" do
      let(:catalog_plan) { create(:catalog_plan, organization:, code: "pro.v2", currency: "USD") }
      let(:plan_wallet) { create(:plan_wallet, organization:, catalog_plan:, code: "pre.paid", currency: "USD") }

      it "returns the wallet template's alerts" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:alerts].map { it[:code] }).to eq(%w[low_ongoing low_balance])
      end
    end

    context "when the alerts have thresholds", :bullet do
      before do
        [alert, ongoing_alert].each do |wallet_alert|
          create_threshold(wallet_alert, code: "low", value: 10_000)
          create_threshold(wallet_alert, code: "empty", value: 0)
        end
      end

      it "renders them without a query per alert" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:alerts].map { it[:thresholds].map { |threshold| threshold[:code] } }).to eq([%w[empty low]] * 2)
      end
    end

    context "with pagination parameters" do
      let(:query) { {page: 2, per_page: 1} }

      it "returns a bad request error for each parameter" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json[:details]).to eq([{code: "not_paginated", field: "page", meta: {}}, {code: "not_paginated", field: "per_page", meta: {}}])
      end
    end

    context "when the wallet template does not exist" do
      let(:wallet_code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("plan_wallet")
      end
    end

    context "when the wallet template is deleted" do
      let(:wallet_code) { create(:plan_wallet, organization:, catalog_plan:, code: "old", deleted_at: Time.current).code }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("plan_wallet")
      end
    end

    context "when the plan does not exist" do
      let(:plan_code) { "unknown" }

      it "returns a not found error on the wallet template" do
        subject

        expect(response).to be_v2_not_found_error("plan_wallet")
      end
    end

    context "when the wallet template belongs to a plan of another organization" do
      let(:other_organization) { create(:organization, feature_flags:) }
      let(:other_plan) { create(:catalog_plan, organization: other_organization, code: "shared_plan", currency: "USD") }
      let(:other_wallet) { create(:plan_wallet, organization: other_organization, catalog_plan: other_plan, code: "shared", currency: "USD") }
      let(:plan_code) { "shared_plan" }
      let(:wallet_code) { "shared" }

      before { create(:plan_wallet_alert, organization: other_organization, plan_wallet: other_wallet) }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("plan_wallet")
      end
    end
  end

  describe "GET /api/v2/plans/:plan_code/wallets/:wallet_code/alerts/:code" do
    subject { get_with_token(organization, "/api/v2/plans/#{plan_code}/wallets/#{wallet_code}/alerts/#{code}") }

    let(:code) { alert.code }

    before do
      create_threshold(alert, code: "low", value: 10_000, notify_on: %w[triggered resolved])
      create_threshold(alert, code: "empty", value: 0)
    end

    include_examples "requires API permission", "alert", "read"
    include_examples "requires the catalog_wallets flag"

    it "returns the alert template, its thresholds by value and in cents" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:alert]).to eq(
        lago_id: alert.id,
        lago_wallet_id: plan_wallet.id,
        wallet_code: "prepaid",
        currency: "USD",
        plan_code: "pro",
        lago_contract_id: nil,
        external_contract_id: nil,
        contract_code: nil,
        external_customer_id: nil,
        code: "low_balance",
        name: "Low balance",
        alert_type: "balance",
        direction: "decreasing",
        thresholds: [
          {code: "empty", value: "0.0", recurring: false, notify_on: %w[triggered]},
          {code: "low", value: "10000.0", recurring: false, notify_on: %w[triggered resolved]}
        ],
        previous_value: nil,
        last_processed_at: nil,
        created_at: alert.created_at.iso8601(6),
        updated_at: alert.updated_at.iso8601(6)
      )
    end

    context "when the plan, wallet and alert codes contain a dot" do
      let(:catalog_plan) { create(:catalog_plan, organization:, code: "pro.v2", currency: "USD") }
      let(:plan_wallet) { create(:plan_wallet, organization:, catalog_plan:, code: "pre.paid", currency: "USD") }
      let(:alert) { create(:plan_wallet_alert, organization:, plan_wallet:, code: "low.balance") }

      it "returns the alert" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:alert].slice(:plan_code, :wallet_code, :code)).to eq(plan_code: "pro.v2", wallet_code: "pre.paid", code: "low.balance")
      end
    end

    context "when its code is the last segment of the list route" do
      let(:alert) { create(:plan_wallet_alert, organization:, plan_wallet:, code: "alerts") }

      it "returns the alert, not the list" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:alert][:lago_id]).to eq(alert.id)
      end
    end

    context "when it does not exist" do
      let(:code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("alert")
      end
    end

    context "when its code is the one of another wallet template's alert" do
      let(:code) { "other_wallet_alert" }

      before do
        create(:plan_wallet_alert, organization:, plan_wallet: create(:plan_wallet, organization:, catalog_plan:), code: "other_wallet_alert")
      end

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("alert")
      end
    end

    context "when the wallet template does not exist" do
      let(:wallet_code) { "unknown" }

      it "returns a not found error on the wallet template" do
        subject

        expect(response).to be_v2_not_found_error("plan_wallet")
      end
    end

    context "when the plan does not exist" do
      let(:plan_code) { "unknown" }

      it "returns a not found error on the wallet template" do
        subject

        expect(response).to be_v2_not_found_error("plan_wallet")
      end
    end

    context "when the alert belongs to a plan of another organization" do
      let(:other_organization) { create(:organization, feature_flags:) }
      let(:other_plan) { create(:catalog_plan, organization: other_organization, code: "shared_plan", currency: "USD") }
      let(:other_wallet) { create(:plan_wallet, organization: other_organization, catalog_plan: other_plan, code: "shared", currency: "USD") }
      let(:plan_code) { "shared_plan" }
      let(:wallet_code) { "shared" }
      let(:code) { "shared_alert" }

      before { create(:plan_wallet_alert, organization: other_organization, plan_wallet: other_wallet, code: "shared_alert") }

      it "returns a not found error on the wallet template" do
        subject

        expect(response).to be_v2_not_found_error("plan_wallet")
      end
    end
  end

  describe "POST /api/v2/plans/:plan_code/wallets/:wallet_code/alerts" do
    subject { post_with_token(organization, "/api/v2/plans/#{plan_code}/wallets/#{wallet_code}/alerts", {alert: create_params}) }

    let(:create_params) do
      {
        code: "low_balance",
        name: "Low balance",
        alert_type: "balance",
        thresholds: [
          {code: "low", value: "10000", notify_on: %w[triggered resolved]},
          {code: "critical", value: 2000, notify_on: %w[triggered resolved]},
          {code: "empty", value: "0"}
        ]
      }
    end

    include_examples "requires API permission", "alert", "write"
    include_examples "requires the catalog_wallets flag"

    it "creates the alert template and renders it, without a webhook" do
      subject

      expect(response).to have_http_status(:ok)
      created = plan_wallet.alerts.sole
      expect(created).to have_attributes(code: "low_balance", name: "Low balance", alert_type: "balance")
      expect(json).to eq(alert: alert_json(created, thresholds: [
        {code: "empty", value: "0.0", recurring: false, notify_on: %w[triggered]},
        {code: "critical", value: "2000.0", recurring: false, notify_on: %w[triggered resolved]},
        {code: "low", value: "10000.0", recurring: false, notify_on: %w[triggered resolved]}
      ]))
      expect(SendWebhookJob).not_to have_been_enqueued
    end

    context "with a fraction of a cent" do
      let(:create_params) { super().merge(thresholds: [{value: "1000.5"}]) }

      it "returns a validation error on its value and creates nothing" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: "thresholds[0].value", meta: {}}])
        expect(plan_wallet.alerts).to be_empty
      end
    end

    context "with a plain notify_on" do
      let(:create_params) { super().merge(thresholds: [{code: "low", value: 1000, notify_on: "resolved"}]) }

      it "returns a validation error on its notify_on rather than ignoring it" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: "thresholds[0].notify_on", meta: {}}])
      end
    end

    context "with a value that is not a number in the second threshold" do
      let(:create_params) { super().merge(thresholds: [{value: 1000}, {value: "abc"}]) }

      it "returns a validation error on that threshold's value and creates nothing" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: "thresholds[1].value", meta: {}}])
        expect(plan_wallet.alerts).to be_empty
      end
    end

    context "with unknown fields on a threshold, one of them a column" do
      let(:create_params) do
        super().merge(thresholds: [{code: "low", value: 1000, colour: "red", organization_id: create(:organization).id}])
      end

      it "creates the alert without them, in the organization of the request" do
        subject

        expect(response).to have_http_status(:ok)
        expect(plan_wallet.alerts.sole.thresholds.pluck(:organization_id, :code, :value)).to eq([[organization.id, "low", 1000]])
      end
    end

    {code: ["low_balance"], name: {text: "Low balance"}}.each do |field, value|
      context "with a #{field} that is not a single value" do
        let(:create_params) { super().merge(field => value) }

        it "returns a validation error on it and creates nothing" do
          subject

          expect(response).to have_http_status(:unprocessable_content)
          expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: field.to_s, meta: {}}])
          expect(plan_wallet.alerts).to be_empty
        end
      end
    end

    context "with an unknown alert type" do
      let(:create_params) { super().merge(alert_type: "credits") }

      it "returns a validation error on the alert type" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "invalid_type", field: "alert_type", meta: {}}])
      end
    end

    context "when the code is taken on the wallet template" do
      let(:create_params) { super().merge(alert_type: "ongoing_balance") }

      before { alert }

      it "returns a validation error on the code" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_already_exist", field: "code", meta: {}}])
      end
    end

    context "when the wallet template already has an alert of this type" do
      let(:create_params) { super().merge(code: "other_code") }

      before { alert }

      it "returns a validation error on the request" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "alert_already_exists", field: "base", meta: {}}])
      end
    end

    context "without the alert parameter" do
      subject { post_with_token(organization, "/api/v2/plans/#{plan_code}/wallets/#{wallet_code}/alerts", {}) }

      it "returns a bad request error" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("missing_parameter")
      end
    end

    context "with an alert that is not an object" do
      subject { post_with_token(organization, "/api/v2/plans/#{plan_code}/wallets/#{wallet_code}/alerts", {alert: "low_balance"}) }

      it "returns a bad request error and creates nothing" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(code: "missing_parameter", details: [{code: "missing", field: "alert", meta: {}}])
        expect(plan_wallet.alerts).to be_empty
      end
    end

    context "when the wallet template does not exist" do
      let(:wallet_code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("plan_wallet")
      end
    end
  end

  describe "PUT /api/v2/plans/:plan_code/wallets/:wallet_code/alerts/:code" do
    subject { put_with_token(organization, "/api/v2/plans/#{plan_code}/wallets/#{wallet_code}/alerts/#{code}", {alert: update_params}) }

    let(:code) { alert.code }
    let(:update_params) { {name: "Prepaid running low", thresholds: [{code: "low", value: "5000"}]} }

    before { create_threshold(alert, code: "low", value: 10_000, notify_on: %w[triggered resolved]) }

    include_examples "requires API permission", "alert", "write"
    include_examples "requires the catalog_wallets flag"

    it "renames it and replaces its thresholds, keeping an omitted notify_on, without a webhook" do
      subject

      expect(response).to have_http_status(:ok)
      expect(json).to eq(alert: alert_json(alert.reload, thresholds: [
        {code: "low", value: "5000.0", recurring: false, notify_on: %w[triggered resolved]}
      ]))
      expect(alert.name).to eq("Prepaid running low")
      expect(SendWebhookJob).not_to have_been_enqueued
    end

    context "with a null name" do
      let(:update_params) { {name: nil} }

      it "clears the name and keeps the thresholds" do
        subject

        expect(response).to have_http_status(:ok)
        expect(alert.reload.name).to be_nil
        expect(json[:alert][:thresholds].map { it[:value] }).to eq(["10000.0"])
      end
    end

    context "with a null list of thresholds" do
      let(:update_params) { {thresholds: nil} }

      it "returns a validation error on the thresholds and keeps them" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_is_mandatory", field: "thresholds", meta: {}}])
        expect(alert.thresholds.pluck(:value)).to eq([10_000])
      end
    end

    context "with a threshold that is not an object" do
      let(:update_params) { {thresholds: [{code: "low", value: "5000"}, 2000]} }

      it "returns a validation error on the item rather than dropping it" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: "thresholds[1]", meta: {}}])
        expect(alert.thresholds.pluck(:value)).to eq([10_000])
      end
    end

    {"an object" => {resolved: true}, "a list holding an object" => [{resolved: true}], "a list holding a list" => [%w[triggered]]}
      .each do |shape, notify_on|
        context "with a notify_on that is #{shape}" do
          let(:update_params) { {thresholds: [{code: "low", value: "5000", notify_on:}]} }

          it "returns a validation error on its notify_on and keeps the thresholds" do
            subject

            expect(response).to have_http_status(:unprocessable_content)
            expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: "thresholds[0].notify_on", meta: {}}])
            expect(alert.thresholds.pluck(:value, :notify_on)).to eq([[10_000, %w[triggered resolved]]])
          end
        end
      end

    {code: ["low"], recurring: [true]}.each do |field, value|
      context "with a #{field} that is a list" do
        let(:update_params) { {thresholds: [{code: "low", value: "5000"}.merge(field => value)]} }

        it "returns a validation error on its #{field} and keeps the thresholds" do
          subject

          expect(response).to have_http_status(:unprocessable_content)
          expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: "thresholds[0].#{field}", meta: {}}])
          expect(alert.thresholds.pluck(:value)).to eq([10_000])
        end
      end
    end

    context "with a name that is a list" do
      let(:update_params) { {name: ["Prepaid running low"]} }

      it "returns a validation error on the name and keeps it" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: "name", meta: {}}])
        expect(alert.reload.name).to eq("Low balance")
      end
    end

    context "with a code that is a list" do
      let(:update_params) { {code: ["new_code"], name: "Prepaid running low"} }

      it "returns a validation error on the code and changes nothing" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_cannot_be_changed", field: "code", meta: {}}])
        expect(alert.reload.name).to eq("Low balance")
      end
    end

    context "with the code and the type" do
      let(:update_params) { {name: "Prepaid running low", code: "new_code", alert_type: "ongoing_balance"} }

      it "returns a validation error on each of them and changes nothing" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(
          code: "validation_errors",
          details: [
            {code: "value_cannot_be_changed", field: "code", meta: {}},
            {code: "value_cannot_be_changed", field: "alert_type", meta: {}}
          ]
        )
        expect(alert.reload.name).to eq("Low balance")
      end
    end

    context "with a negative balance threshold" do
      let(:update_params) { {thresholds: [{value: "-100"}]} }

      it "returns a validation error on its value and keeps the thresholds" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: "thresholds[0].value", meta: {}}])
        expect(alert.thresholds.pluck(:value)).to eq([10_000])
      end
    end

    context "when it does not exist" do
      let(:code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("alert")
      end
    end

    context "when the wallet template does not exist" do
      let(:wallet_code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("plan_wallet")
      end
    end
  end

  describe "DELETE /api/v2/plans/:plan_code/wallets/:wallet_code/alerts/:code" do
    subject { delete_with_token(organization, "/api/v2/plans/#{plan_code}/wallets/#{wallet_code}/alerts/#{code}") }

    let(:code) { alert.code }

    before { create_threshold(alert, code: "low", value: 10_000) }

    include_examples "requires API permission", "alert", "write"
    include_examples "requires the catalog_wallets flag"

    it "deletes it for good with its thresholds and renders it" do
      subject

      expect(response).to have_http_status(:ok)
      expect(json).to eq(alert: alert_json(alert, thresholds: []))
      expect(UsageMonitoring::PlanWalletAlert.where(id: alert.id)).to be_empty
      expect(UsageMonitoring::CatalogWalletAlertThreshold.where(plan_wallet_alert_id: alert.id)).to be_empty
    end

    context "when it does not exist" do
      let(:code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("alert")
      end
    end

    context "when the wallet template does not exist" do
      let(:wallet_code) { "unknown" }

      it "returns a not found error and deletes nothing" do
        subject

        expect(response).to be_v2_not_found_error("plan_wallet")
        expect(UsageMonitoring::PlanWalletAlert.where(id: alert.id)).to exist
      end
    end
  end
end
