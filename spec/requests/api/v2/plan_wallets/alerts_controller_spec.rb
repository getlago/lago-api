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
        external_contract_id: nil,
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
end
