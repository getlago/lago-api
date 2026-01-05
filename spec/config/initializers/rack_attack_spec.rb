# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rack::Attack", type: :request, rack_attack: true do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:)}
  let(:api_key) { create(:api_key, organization:) }
  let(:metric) { create(:billable_metric, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, customer:, organization:, plan:, started_at: 1.month.ago) }

  let(:batch_params) do
    [
      {
        code: metric.code,
        transaction_id: SecureRandom.uuid,
        external_subscription_id: subscription.external_id,
        timestamp: Time.current.to_i
      }
    ]
  end

  let(:headers) do
    {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key.value}"
    }
  end

  describe "events/batch throttle" do
    context "when under the rate limit" do
      it "allow requests" do
        10.times do
          post "/api/v1/events/batch",
            params: {events: [{
              code: metric.code,
              transaction_id: SecureRandom.uuid,
              external_subscription_id: subscription.external_id,
              timestamp: Time.current.to_i
            }]}.to_json,
            headers:
        end

        expect(response).to have_http_status(:ok)
      end
    end

    context "when exceeding the rate limit" do
      it "returns 429 Too Many Requests" do
        11.times do
          post "/api/v1/events/batch",
            params: {events: [{
              code: metric.code,
              transaction_id: SecureRandom.uuid,
              external_subscription_id: subscription.external_id,
              timestamp: Time.current.to_i
            }]}.to_json,
            headers:
        end

        expect(response).to have_http_status(:too_many_requests)
        expect(json[:status]).to eq(429)
        expect(json[:code]).to eq("rate_limit_exceeded")
        expect(response.headers["Retry-After"]).to be_present
      end
    end

    context "when different organizations make requests" do
      let(:other_organization) { create(:organization) }
      let(:other_customer) { create(:customer, organization: other_organization) }
      let(:other_metric) { create(:billable_metric, organization: other_organization) }
      let(:other_plan) { create(:plan, organization: other_organization) }
      let(:other_subscription) { create(:subscription, customer: other_customer, organization: other_organization, plan: other_plan, started_at: 1.month.ago) }

      let(:other_headers) do
        {
          "Content-Type" => "application/json",
          "Authorization" => "Bearer #{other_organization.api_keys.first.value}"
        }
      end

      it "tracks rate limits separately per organization" do
        10.times do
          post "/api/v1/events/batch",
            params: {events: [{
              code: metric.code,
              transaction_id: SecureRandom.uuid,
              external_subscription_id: subscription.external_id,
              timestamp: Time.current.to_i
            }]}.to_json,
            headers:
        end

        post "/api/v1/events/batch",
          params: {events: [{
            code: other_metric.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: other_subscription.external_id,
            timestamp: Time.current.to_i
          }]}.to_json,
          headers: other_headers

        expect(response).to have_http_status(:ok)
      end
    end

    context "with custom organization rate limit" do
      before do
        organization.update!(api_rate_limits: {"events_batch" => 5})
      end

      it "respects the custom limit" do
        6.times do
          post "/api/v1/events/batch",
            params: {events: [{
              code: metric.code,
              transaction_id: SecureRandom.uuid,
              external_subscription_id: subscription.external_id,
              timestamp: Time.current.to_i
            }]}.to_json,
            headers:
        end

        expect(response).to have_http_status(:too_many_requests)
      end
    end
  end
end
