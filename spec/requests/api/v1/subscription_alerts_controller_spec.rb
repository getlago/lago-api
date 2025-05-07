# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::SubscriptionAlertsController, type: :request do
  let(:external_id) { "sub+1" }
  let(:code) { "my-alert" }
  let(:organization) { create(:organization) }
  let(:subscription) { create(:subscription, external_id:, customer: create(:customer, organization: organization)) }
  let(:alert) { create(:alert, :processed, code:, subscription_external_id: external_id, organization:) }

  before do
    subscription
    alert
  end

  describe "GET /api/v1/subscriptions/:external_id/alerts" do
    subject { get_with_token(organization, "/api/v1/subscriptions/#{external_id}/alerts") }

    include_examples "requires API permission", "subscription", "read"

    it do
      subject
      expect(json[:alerts].sole).to include({
        code:,
        lago_id: alert.id,
        previous_value: "800.0",
        name: "General Alert",
        created_at: be_present,
        updated_at: be_present,
        deleted_at: be_nil
      })
      expect(json[:meta]).to eq({
        current_page: 1,
        next_page: nil,
        prev_page: nil,
        total_pages: 1,
        total_count: 1
      })
    end

    context "when there is no alerts" do
      let(:alert) { nil }

      it do
        subject
        expect(json[:alerts]).to be_empty
        expect(json[:meta][:total_count]).to eq 0
      end
    end
  end

  describe "POST /api/v1/subscriptions/:external_id/alerts" do
    subject { post_with_token(organization, "/api/v1/subscriptions/#{external_id}/alerts", {alert: params}) }

    let(:alert) { nil }
    let(:params) do
      {
        code: "test",
        name: "New Alert",
        alert_type: "usage_amount",
        thresholds: [
          {code: :notice, value: 1000},
          {code: :warn, value: 5000},
          {code: :alert, value: 1000, recurring: true}
        ]
      }
    end

    include_examples "requires API permission", "subscription", "write"

    it do
      subject

      pp json
      expect(json[:alert]).to include({
        lago_id: be_present,
        code: "test",
        name: "New Alert",
        previous_value: "0.0",
        last_processed_at: be_nil,
        created_at: be_present,
        updated_at: be_present,
        deleted_at: be_nil
      })
    end

    context "when payload is missing required param" do
      let(:alert) { nil }

      [:code, :alert_type, :thresholds].each do |field|
        it do
          params.delete(field)
          subject
          expect(json).to eq({
            code: "validation_errors",
            error: "Unprocessable Entity",
            error_details: {field => ["#{field}_must_be_present"]},
            status: 422
          })
        end
      end
    end
  end

  describe "GET /api/v1/subscriptions/:external_id/alerts/:code" do
    subject { get_with_token(organization, "/api/v1/subscriptions/#{external_id}/alerts/#{code}") }

    include_examples "requires API permission", "subscription", "read"

    it do
      subject
      expect(json[:alert]).to include({
        code:,
        lago_id: alert.id,
        previous_value: "800.0",
        name: "General Alert",
        created_at: be_present,
        updated_at: be_present,
        deleted_at: be_nil
      })
    end

    context "when alert is not found" do
      let(:alert) { nil }

      it do
        expect(subject).to eq 404
        expect(json).to eq({
          code: "alert_not_found",
          error: "Not Found",
          status: 404
        })
      end
    end
  end

  describe "DELETE /api/v1/subscriptions/:external_id/alerts/:code" do
    subject { delete_with_token(organization, "/api/v1/subscriptions/#{external_id}/alerts/#{code}") }

    include_examples "requires API permission", "subscription", "write"

    it do
      subject
      expect(Time.parse(json[:alert][:deleted_at])).to be_within(5.seconds).of(Time.current)
    end

    context "when alert is not found" do
      let(:alert) { nil }

      it do
        expect(subject).to eq 404
        expect(json).to eq({
          code: "alert_not_found",
          error: "Not Found",
          status: 404
        })
      end
    end
  end
end
