# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::ContractWallets::AlertsController do
  let(:organization) { create(:organization, feature_flags:) }
  let(:feature_flags) { %w[product_catalog catalog_wallets] }
  let(:customer) { create(:customer, organization:, external_id: "acme", currency: "USD") }
  let(:contract) { create(:contract, :pending, organization:, customer:, external_id: "acme-pro") }
  let(:contract_wallet) { create(:catalog_wallet, organization:, customer:, contract:, code: "prepaid") }
  let(:alert) { create(:catalog_wallet_alert, organization:, catalog_wallet: contract_wallet, code: "low_balance", name: "Low balance") }
  let(:external_id) { contract.external_id }
  let(:wallet_code) { contract_wallet.code }
  let(:path) { "/api/v2/contracts/#{external_id}/wallets/#{wallet_code}/alerts" }

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
    create(:catalog_wallet_alert_threshold, organization:, catalog_wallet_alert: alert, **attributes)
  end

  def alert_json(alert, thresholds:, previous_value: nil, last_processed_at: nil)
    {
      lago_id: alert.id,
      lago_wallet_id: contract_wallet.id,
      wallet_code: "prepaid",
      currency: "USD",
      plan_code: nil,
      lago_contract_id: contract.id,
      external_contract_id: "acme-pro",
      contract_code: contract.code,
      external_customer_id: "acme",
      code: alert.code,
      name: alert.name,
      alert_type: alert.alert_type,
      direction: "decreasing",
      thresholds:,
      previous_value:,
      last_processed_at:,
      created_at: alert.created_at.iso8601(6),
      updated_at: alert.updated_at.iso8601(6)
    }
  end

  describe "GET /api/v2/contracts/:external_id/wallets/:wallet_code/alerts" do
    subject { get_with_token(organization, path, query) }

    let(:query) { {} }
    let(:ongoing_alert) do
      create(:catalog_wallet_alert, organization:, catalog_wallet: contract_wallet, alert_type: "ongoing_balance", code: "low_ongoing", created_at: 1.minute.from_now)
    end

    before do
      alert
      ongoing_alert
      create(:catalog_wallet_alert, organization:, catalog_wallet: create(:catalog_wallet, organization:, customer:, contract:))
    end

    include_examples "requires API permission", "alert", "read"
    include_examples "requires the catalog_wallets flag"

    it "returns the wallet's alerts, newest first and unpaginated" do
      subject

      expect(response).to have_http_status(:success)
      expect(json.keys).to eq([:alerts])
      expect(json[:alerts].map { it[:code] }).to eq(%w[low_ongoing low_balance])
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

    context "when the external id and the wallet code contain a dot" do
      let(:contract) { create(:contract, :pending, organization:, customer:, external_id: "acme.pro") }
      let(:contract_wallet) { create(:catalog_wallet, organization:, customer:, contract:, code: "pre.paid") }

      it "returns the wallet's alerts" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:alerts].map { it[:code] }).to eq(%w[low_ongoing low_balance])
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

    context "when an ended contract reuses the external id" do
      let(:ended_contract) { create(:contract, :terminated, organization:, customer:, external_id: "acme-pro", started_at: 2.months.ago) }

      before { create(:catalog_wallet, organization:, customer:, contract: ended_contract, code: "prepaid") }

      it "asks for the contract code" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_is_mandatory", field: "contract_code", meta: {}}])
      end

      context "with the contract code" do
        let(:query) { {contract_code: contract.code} }

        it "returns the alerts of that contract's wallet" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:alerts].map { it[:code] }).to eq(%w[low_ongoing low_balance])
        end
      end
    end

    context "when the wallet does not exist" do
      let(:wallet_code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("contract_wallet")
      end
    end

    context "when the wallet was removed from the contract" do
      let(:wallet_code) { create(:catalog_wallet, organization:, customer:, contract:, code: "old", deleted_at: Time.current).code }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("contract_wallet")
      end
    end

    context "when the wallet has ended" do
      let(:contract_wallet) { create(:catalog_wallet, organization:, customer:, contract:, code: "prepaid", terminated_at: Time.current) }

      it "still returns its alerts" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:alerts].map { it[:code] }).to eq(%w[low_ongoing low_balance])
      end
    end

    context "when the contract does not exist" do
      let(:external_id) { "unknown" }

      it "returns a not found error on the wallet" do
        subject

        expect(response).to be_v2_not_found_error("contract_wallet")
      end
    end

    context "when the wallet belongs to a contract of another organization with the same external id" do
      let(:other_organization) { create(:organization, feature_flags:) }
      let(:other_contract) { create(:contract, organization: other_organization, external_id: "shared") }
      let(:external_id) { "shared" }
      let(:wallet_code) { "shared_wallet" }

      before do
        other_wallet = create(:catalog_wallet, organization: other_organization, contract: other_contract, code: "shared_wallet")
        create(:catalog_wallet_alert, organization: other_organization, catalog_wallet: other_wallet)
      end

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("contract_wallet")
      end
    end
  end

  describe "GET /api/v2/contracts/:external_id/wallets/:wallet_code/alerts/:code" do
    subject { get_with_token(organization, "#{path}/#{code}") }

    let(:contract) { create(:contract, organization:, customer:, external_id: "acme-pro") }
    let(:alert) do
      create(:catalog_wallet_alert, organization:, catalog_wallet: contract_wallet, code: "low_balance", name: "Low balance", previous_value: 1_500, last_processed_at: Time.zone.parse("2026-11-24T10:00:00Z"))
    end
    let(:code) { alert.code }

    before do
      create_threshold(alert, code: "low", value: 2_000, notify_on: %w[triggered resolved])
      create_threshold(alert, code: "empty", value: 0)
    end

    include_examples "requires API permission", "alert", "read"
    include_examples "requires the catalog_wallets flag"

    it "returns the alert with its thresholds by value and its evaluation state" do
      subject

      expect(response).to have_http_status(:success)
      expect(json).to eq(alert: alert_json(
        alert,
        thresholds: [
          {code: "empty", value: "0.0", recurring: false, notify_on: %w[triggered]},
          {code: "low", value: "2000.0", recurring: false, notify_on: %w[triggered resolved]}
        ],
        previous_value: "1500.0",
        last_processed_at: "2026-11-24T10:00:00.000000Z"
      ))
    end

    context "when its code is the last segment of the list route" do
      let(:alert) { create(:catalog_wallet_alert, organization:, catalog_wallet: contract_wallet, code: "alerts") }

      it "returns the alert, not the list" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:alert][:code]).to eq("alerts")
      end
    end

    context "when its code is the last segment of the transactions route" do
      let(:alert) { create(:catalog_wallet_alert, organization:, catalog_wallet: contract_wallet, code: "transactions") }

      it "returns the alert, not the wallet's transactions" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:alert][:code]).to eq("transactions")
      end
    end

    context "when its code is the one of another wallet's alert" do
      let(:code) { "other_alert" }

      before do
        create(:catalog_wallet_alert, organization:, catalog_wallet: create(:catalog_wallet, organization:, customer:, contract:), code: "other_alert")
      end

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("alert")
      end
    end

    context "when its code contains a dot" do
      let(:alert) { create(:catalog_wallet_alert, organization:, catalog_wallet: contract_wallet, code: "low.balance") }

      it "returns the alert" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:alert][:code]).to eq("low.balance")
      end
    end

    context "when another contract has a wallet and an alert with the same codes" do
      let(:other_contract) { create(:contract, organization:, customer:, external_id: "acme-other") }
      let(:other_wallet) { create(:catalog_wallet, organization:, customer:, contract: other_contract, code: "prepaid") }
      let(:other_alert) { create(:catalog_wallet_alert, organization:, catalog_wallet: other_wallet, code: "low_balance") }

      before { other_alert }

      it "returns the alert of this contract's wallet" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:alert][:lago_id]).to eq(alert.id)
      end

      context "when the other contract is asked for" do
        let(:external_id) { other_contract.external_id }

        it "returns the alert of the other contract's wallet" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:alert][:lago_id]).to eq(other_alert.id)
        end
      end
    end

    context "when the wallet does not exist" do
      let(:wallet_code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("contract_wallet")
      end
    end
  end

  describe "POST /api/v2/contracts/:external_id/wallets/:wallet_code/alerts" do
    subject { post_with_token(organization, path, {alert: create_params}) }

    let(:contract_wallet) { create(:catalog_wallet, organization:, customer:, contract:, code: "prepaid", balance_cents: 1_500) }
    let(:create_params) do
      {
        code: "low_balance",
        name: "Low balance",
        alert_type: "balance",
        thresholds: [{code: "low", value: "2000", notify_on: %w[triggered resolved]}, {code: "empty", value: "0"}]
      }
    end
    let(:thresholds_json) do
      [
        {code: "empty", value: "0.0", recurring: false, notify_on: %w[triggered]},
        {code: "low", value: "2000.0", recurring: false, notify_on: %w[triggered resolved]}
      ]
    end

    include_examples "requires API permission", "alert", "write"
    include_examples "requires the catalog_wallets flag"

    it "creates the alert on a pending contract without a previous value, though the wallet holds 1500, and sends nothing" do
      subject

      expect(response).to have_http_status(:ok)
      created = contract_wallet.alerts.sole
      expect(created).to have_attributes(code: "low_balance", previous_value: nil, last_processed_at: nil)
      expect(json).to eq(alert: alert_json(created, thresholds: thresholds_json))
      expect(created.all_triggered_alerts).to be_empty
      expect(SendWebhookJob).not_to have_been_enqueued
    end

    context "when the contract is a draft" do
      let(:contract) { create(:contract, :draft, organization:, customer:, external_id: "acme-pro") }

      it "creates the alert without a previous value, though the wallet holds 1500" do
        subject

        expect(response).to have_http_status(:ok)
        expect(contract_wallet.alerts.sole).to have_attributes(code: "low_balance", previous_value: nil, last_processed_at: nil)
      end
    end

    context "when the contract is active and the wallet holds 1500" do
      let(:contract) { create(:contract, organization:, customer:, external_id: "acme-pro") }

      it "watches from the balance, seeding the opted-in line already past and sending nothing" do
        freeze_time do
          subject

          expect(response).to have_http_status(:ok)
          created = contract_wallet.alerts.sole
          # 2000 is above the balance of 1500 and opted in to resolution; 0 is below it
          expect(json).to eq(alert: alert_json(created, thresholds: thresholds_json, previous_value: "1500.0", last_processed_at: Time.current.iso8601(6)))
          seeded = created.all_triggered_alerts.sole
          expect(seeded).to have_attributes(kind: "seeded", current_value: 1_500)
          expect(seeded.crossed_thresholds.map { it["code"] }).to eq(["low"])
          expect(SendWebhookJob).not_to have_been_enqueued
        end
      end

      context "when the wallet is empty" do
        let(:contract_wallet) { create(:catalog_wallet, organization:, customer:, contract:, code: "prepaid") }

        it "creates a balance alert that waits for money, and sends nothing" do
          subject

          expect(response).to have_http_status(:ok)
          expect(json[:alert]).to include(previous_value: nil, last_processed_at: nil)
          expect(contract_wallet.alerts.sole.all_triggered_alerts).to be_empty
          expect(SendWebhookJob).not_to have_been_enqueued
        end
      end
    end

    context "when the wallet has ended" do
      let(:contract_wallet) { create(:catalog_wallet, organization:, customer:, contract:, code: "prepaid", terminated_at: Time.current) }

      it "returns a forbidden error and creates nothing" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json).to eq(code: "wallet_alerts_read_only", details: [])
        expect(contract_wallet.alerts).to be_empty
      end
    end

    context "when the contract has ended" do
      let(:contract) { create(:contract, :terminated, organization:, customer:, external_id: "acme-pro") }

      it "returns a forbidden error and creates nothing" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json).to eq(code: "contract_not_live", details: [])
        expect(contract_wallet.alerts).to be_empty
      end
    end

    context "when the wallet already has an alert of this type" do
      before { alert }

      let(:create_params) { super().merge(code: "other_code") }

      it "returns a validation error on the request" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "alert_already_exists", field: "base", meta: {}}])
      end
    end

    context "without the alert parameter" do
      subject { post_with_token(organization, path, {}) }

      it "returns a bad request error" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("missing_parameter")
      end
    end

    context "when the wallet does not exist" do
      let(:wallet_code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("contract_wallet")
      end
    end
  end

  describe "PUT /api/v2/contracts/:external_id/wallets/:wallet_code/alerts/:code" do
    subject { put_with_token(organization, "#{path}/#{code}", {alert: update_params}) }

    let(:code) { alert.code }
    let(:update_params) { {name: "Running low", thresholds: [{code: "low", value: "5000"}]} }

    before { create_threshold(alert, code: "low", value: 2_000, notify_on: %w[triggered resolved]) }

    include_examples "requires API permission", "alert", "write"
    include_examples "requires the catalog_wallets flag"

    it "renames it and replaces its thresholds, keeping an omitted notify_on, without a webhook" do
      subject

      expect(response).to have_http_status(:ok)
      expect(json).to eq(alert: alert_json(alert.reload, thresholds: [{code: "low", value: "5000.0", recurring: false, notify_on: %w[triggered resolved]}]))
      expect(alert.name).to eq("Running low")
      expect(SendWebhookJob).not_to have_been_enqueued
    end

    context "when the wallet has ended" do
      let(:contract_wallet) { create(:catalog_wallet, organization:, customer:, contract:, code: "prepaid", terminated_at: Time.current) }

      it "returns a forbidden error and changes nothing" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json).to eq(code: "wallet_alerts_read_only", details: [])
        expect(alert.reload.name).to eq("Low balance")
      end
    end

    context "when the contract has ended" do
      before { Contracts::TerminateService.call!(contract: Contract.find(contract.id)) }

      it "returns a not found error, since the end deleted the alert" do
        subject

        expect(response).to be_v2_not_found_error("alert")
      end
    end

    # The alert was read before the end committed: the service reads the contract again under its lock
    context "when the contract ends between the alert lookup and the write" do
      let(:contract) { create(:contract, :terminated, organization:, customer:, external_id: "acme-pro") }

      it "returns a forbidden error and changes nothing" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json).to eq(code: "contract_not_live", details: [])
        expect(alert.reload.name).to eq("Low balance")
      end
    end

    context "when it does not exist" do
      let(:code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("alert")
      end
    end

    context "when the wallet does not exist" do
      let(:wallet_code) { "unknown" }

      it "returns a not found error and changes nothing" do
        subject

        expect(response).to be_v2_not_found_error("contract_wallet")
        expect(alert.reload.name).to eq("Low balance")
      end
    end
  end

  describe "DELETE /api/v2/contracts/:external_id/wallets/:wallet_code/alerts/:code" do
    subject { delete_with_token(organization, "#{path}/#{code}") }

    let(:code) { alert.code }

    before do
      create_threshold(alert, code: "low", value: 2_000)
      create(:catalog_wallet_triggered_alert, organization:, alert:, kind: :seeded, current_value: 1_500, previous_value: 1_500, crossed_thresholds: [{code: "low", value: BigDecimal(2_000), recurring: false}])
    end

    include_examples "requires API permission", "alert", "write"
    include_examples "requires the catalog_wallets flag"

    it "deletes it for good with its thresholds, keeps its history and renders it" do
      subject

      expect(response).to have_http_status(:ok)
      expect(json).to eq(alert: alert_json(alert, thresholds: []))
      expect(UsageMonitoring::CatalogWalletAlert.where(id: alert.id)).to be_empty
      expect(UsageMonitoring::CatalogWalletAlertThreshold.where(catalog_wallet_alert_id: alert.id)).to be_empty
      expect(UsageMonitoring::CatalogWalletTriggeredAlert.where(catalog_wallet_alert_id: alert.id).count).to eq(1)
      expect(SendWebhookJob).not_to have_been_enqueued
    end

    context "when the contract has ended" do
      before { Contracts::TerminateService.call!(contract: Contract.find(contract.id)) }

      it "returns a not found error, since the end deleted the alert" do
        subject

        expect(response).to be_v2_not_found_error("alert")
      end
    end

    # The alert was read before the end committed: the service reads the contract again under its lock
    context "when the contract ends between the alert lookup and the write" do
      let(:contract) { create(:contract, :terminated, organization:, customer:, external_id: "acme-pro") }

      it "returns a forbidden error and deletes nothing" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json).to eq(code: "contract_not_live", details: [])
        expect(UsageMonitoring::CatalogWalletAlert.where(id: alert.id)).to exist
      end
    end

    context "when the wallet has ended" do
      let(:contract_wallet) { create(:catalog_wallet, organization:, customer:, contract:, code: "prepaid", terminated_at: Time.current) }

      it "returns a forbidden error and deletes nothing" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json).to eq(code: "wallet_alerts_read_only", details: [])
        expect(UsageMonitoring::CatalogWalletAlert.where(id: alert.id)).to exist
      end
    end

    context "when it does not exist" do
      let(:code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("alert")
      end
    end

    context "when the wallet does not exist" do
      let(:wallet_code) { "unknown" }

      it "returns a not found error and deletes nothing" do
        subject

        expect(response).to be_v2_not_found_error("contract_wallet")
        expect(UsageMonitoring::CatalogWalletAlert.where(id: alert.id)).to exist
      end
    end
  end
end
