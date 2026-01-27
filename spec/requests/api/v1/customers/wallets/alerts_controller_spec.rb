# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::Customers::Wallets::AlertsController do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:wallet) { create(:wallet, customer:, organization:) }
  let(:code) { "my-wallet-alert" }
  let(:alert) { create(:wallet_balance_amount_alert, :processed, code:, wallet:, organization:) }
  let(:deleted_alert) { create(:wallet_balance_amount_alert, :processed, deleted_at: Time.current, wallet:, organization:, thresholds: []) }

  before do
    alert
    deleted_alert
  end

  RSpec.shared_examples "returns error if customer not found" do
    let(:customer_external_id) { "not-found-id" }

    it do
      subject
      expect(response).to be_not_found_error("customer")
    end
  end

  RSpec.shared_examples "returns error if wallet not found" do
    let(:wallet_id) { "00000000-0000-0000-0000-000000000000" }

    it do
      subject
      expect(response).to be_not_found_error("wallet")
    end
  end

  let(:customer_external_id) { customer.external_id }
  # TODO: Once wallet `code` attribute is added, change to wallet.code
  let(:wallet_id) { wallet.id }

  describe "GET /api/v1/customers/:external_id/wallets/:wallet_id/alerts" do
    subject { get_with_token(organization, "/api/v1/customers/#{customer_external_id}/wallets/#{wallet_id}/alerts") }

    it_behaves_like "requires API permission", "alert", "read"
    it_behaves_like "returns error if customer not found"
    it_behaves_like "returns error if wallet not found"

    context "when there are alerts" do
      it "retrieves a paginated list of alerts" do
        subject
        expect(json[:alerts].sole).to include({
          code:,
          lago_id: alert.id,
          alert_type: "wallet_balance_amount",
          previous_value: "800.0",
          name: "General Alert",
          created_at: be_present
        })
        expect(json[:meta]).to eq({
          current_page: 1,
          next_page: nil,
          prev_page: nil,
          total_pages: 1,
          total_count: 1
        })
      end
    end

    context "when there are no alerts" do
      let(:alert) { nil }

      it do
        subject
        expect(json[:alerts]).to be_empty
        expect(json[:meta][:total_count]).to eq 0
      end
    end
  end

  describe "POST /api/v1/customers/:external_id/wallets/:wallet_id/alerts" do
    subject { post_with_token(organization, "/api/v1/customers/#{customer_external_id}/wallets/#{wallet_id}/alerts", {alert: params}) }

    let(:alert) { nil }
    let(:params) do
      {
        code: "test",
        name: "New Wallet Alert",
        alert_type: "wallet_balance_amount",
        thresholds: [
          {code: :notice, value: 1000},
          {code: :warn, value: 5000},
          {code: :alert, value: 2000, recurring: true}
        ]
      }
    end

    it_behaves_like "requires API permission", "alert", "write"
    it_behaves_like "returns error if customer not found"
    it_behaves_like "returns error if wallet not found"

    it do
      subject

      expect(json[:alert]).to include({
        lago_id: be_present,
        code: "test",
        name: "New Wallet Alert",
        alert_type: "wallet_balance_amount",
        previous_value: "0.0",
        last_processed_at: be_nil,
        created_at: be_present
      })
    end

    context "when alert_type is wallet_credits_balance" do
      let(:params) do
        {
          code: "credits-alert",
          name: "Credits Balance Alert",
          alert_type: "wallet_credits_balance",
          thresholds: [{code: :notice, value: 100}]
        }
      end

      it "creates a wallet_credits_balance alert" do
        subject
        expect(json[:alert]).to include({
          lago_id: be_present,
          code: "credits-alert",
          alert_type: "wallet_credits_balance"
        })
      end
    end

    context "when alert_type is not a wallet type" do
      let(:params) do
        {
          code: "test",
          alert_type: "current_usage_amount",
          thresholds: [{code: :notice, value: 1000}]
        }
      end

      it "returns validation error" do
        subject
        expect(json).to eq({
          code: "validation_errors",
          error: "Unprocessable Entity",
          error_details: {alert_type: ["invalid_for_wallet"]},
          status: 422
        })
      end
    end

    context "when payload is missing required param" do
      %i[code thresholds].each do |field|
        it "returns error when #{field} is missing" do
          params.delete(field)
          subject
          expect(json).to match({
            code: "validation_errors",
            error: "Unprocessable Entity",
            error_details: {field => array_including("value_is_mandatory")},
            status: 422
          })
        end
      end

      it "returns error when alert_type is missing" do
        params.delete(:alert_type)
        subject
        expect(json).to eq({
          code: "validation_errors",
          error: "Unprocessable Entity",
          error_details: {alert_type: ["value_is_mandatory"]},
          status: 422
        })
      end
    end

    context "when alert_type is not supported" do
      let(:params) do
        {
          code: "test",
          alert_type: "not_supported",
          thresholds: [{code: :notice, value: 1000}]
        }
      end

      it do
        subject
        expect(json).to eq({
          code: "validation_errors",
          error: "Unprocessable Entity",
          error_details: {alert_type: ["invalid_type"]},
          status: 422
        })
      end
    end
  end

  describe "GET /api/v1/customers/:external_id/wallets/:wallet_id/alerts/:code" do
    subject { get_with_token(organization, "/api/v1/customers/#{customer_external_id}/wallets/#{wallet_id}/alerts/#{code}") }

    it_behaves_like "requires API permission", "alert", "read"
    it_behaves_like "returns error if customer not found"
    it_behaves_like "returns error if wallet not found"

    it do
      subject
      expect(json[:alert]).to include({
        code:,
        lago_id: alert.id,
        alert_type: "wallet_balance_amount",
        previous_value: "800.0",
        name: "General Alert",
        created_at: be_present
      })
    end

    context "when alert is not found" do
      let(:alert) { nil }

      it do
        subject
        expect(response).to be_not_found_error("alert")
      end
    end
  end

  describe "PUT /api/v1/customers/:external_id/wallets/:wallet_id/alerts/:code" do
    subject { put_with_token(organization, "/api/v1/customers/#{customer_external_id}/wallets/#{wallet_id}/alerts/#{code}", {alert: params}) }

    let(:params) do
      {
        code: "updated-code",
        thresholds: [{code: :notice, value: 88_00}]
      }
    end

    it_behaves_like "requires API permission", "alert", "write"
    it_behaves_like "returns error if customer not found"
    it_behaves_like "returns error if wallet not found"

    it "updates the alert" do
      subject

      expect(json[:alert]).to include({
        lago_id: alert.id,
        lago_organization_id: organization.id,
        code: "updated-code",
        name: "General Alert",
        previous_value: "800.0",
        last_processed_at: be_present,
        created_at: be_present
      })
    end

    context "when alert is not found" do
      let(:alert) { nil }

      it do
        subject
        expect(response).to be_not_found_error("alert")
      end
    end
  end

  describe "DELETE /api/v1/customers/:external_id/wallets/:wallet_id/alerts/:code" do
    subject { delete_with_token(organization, "/api/v1/customers/#{customer_external_id}/wallets/#{wallet_id}/alerts/#{code}") }

    it_behaves_like "requires API permission", "alert", "write"
    it_behaves_like "returns error if customer not found"
    it_behaves_like "returns error if wallet not found"

    it "soft deletes the alert" do
      subject
      expect(alert.reload.deleted_at).to be_within(5.seconds).of(Time.current)
    end

    context "when alert is not found" do
      let(:alert) { nil }

      it do
        subject
        expect(response).to be_not_found_error("alert")
      end
    end
  end
end
