# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::WebhookEndpointsController do
  let_it_be(:organization, refind: true) { create_default(:organization) }

  describe "POST /api/v1/webhook_endpoints" do
    subject do
      post_with_token(
        organization,
        "/api/v1/webhook_endpoints",
        {webhook_endpoint: create_params}
      )
    end

    let_it_be(:organization, refind: true) { create_default(:organization) }
    let(:create_params) do
      {
        webhook_url: Faker::Internet.url,
        signature_algo: "jwt",
        name: "Test Webhook",
        event_types: ["customer.created", "customer.updated"]
      }
    end

    include_context "with mocked security logger"
    include_examples "requires API permission", "webhook_endpoint", "write"

    context "with valid parameters" do
      it "returns a success" do
        subject

        expect(response).to have_http_status(:success)

        expect(json[:webhook_endpoint][:webhook_url]).to eq(create_params[:webhook_url])
        expect(json[:webhook_endpoint][:signature_algo]).to eq("jwt")
        expect(json[:webhook_endpoint][:name]).to eq(create_params[:name])
        expect(json[:webhook_endpoint][:event_types]).to eq(create_params[:event_types])
        expect(json[:webhook_endpoint][:signing_keys]).to eq([])
      end
    end

    context "without a signature_algo" do
      let(:create_params) { super().except(:signature_algo) }

      it "signs with JWT" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:webhook_endpoint][:signature_algo]).to eq("jwt")
        expect(organization.webhook_endpoints.find(json[:webhook_endpoint][:lago_id]).signing_keys.count).to eq(0)
      end
    end

    context "with the hmac signature_algo" do
      let(:create_params) { super().merge(signature_algo: "hmac") }

      it "creates an HMAC endpoint" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:webhook_endpoint][:signature_algo]).to eq("hmac")
        expect(json[:webhook_endpoint][:signing_keys]).to eq([])
      end
    end

    context "with an unknown signature_algo" do
      let(:create_params) { super().merge(signature_algo: "md5") }

      it "returns unprocessable_content error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(signature_algo: ["value_is_invalid"])
      end
    end

    context "with the standard_webhooks signature_algo" do
      let(:create_params) { super().merge(signature_algo: "standard_webhooks") }

      it "returns a validation error without the standard_webhooks_signature flag" do
        expect { subject }.not_to change(WebhookEndpoint, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(signature_algo: ["value_is_invalid"])
      end

      context "with the standard_webhooks_signature flag" do
        let(:organization) { create(:organization, feature_flags: ["standard_webhooks_signature"]) }

        it "creates the endpoint with exactly one signing key" do
          expect { subject }.to change(WebhookEndpointSigningKey, :count).by(1)

          expect(response).to have_http_status(:success)
          expect(json[:webhook_endpoint][:signature_algo]).to eq("standard_webhooks")
          webhook_endpoint = organization.webhook_endpoints.find(json[:webhook_endpoint][:lago_id])
          expect(webhook_endpoint.signature_algo).to eq("standard_webhooks")
          expect(webhook_endpoint.signing_keys.count).to eq(1)
          signing_key = webhook_endpoint.signing_keys.sole
          expect(json[:webhook_endpoint][:signing_keys]).to eq(
            [{lago_id: signing_key.id, secret_key: signing_key.secret, created_at: signing_key.created_at.iso8601}]
          )
          expect(signing_key.secret).to start_with("whsec_")
        end

        context "when the API log is produced", :capture_kafka_messages do
          include_context "with API log infrastructure"

          it "masks the secret_key of every signing key" do
            subject

            expect(response).to have_http_status(:success)
            signing_key = organization.webhook_endpoints.find(json[:webhook_endpoint][:lago_id]).signing_keys.sole
            logged_endpoint = api_log_payload["request_response"]["webhook_endpoint"]
            expect(logged_endpoint["signing_keys"]).to eq(
              [{"lago_id" => signing_key.id, "secret_key" => "[FILTERED]", "created_at" => signing_key.created_at.iso8601}]
            )
            expect(logged_endpoint["lago_id"]).to eq(signing_key.webhook_endpoint_id)
            expect(logged_endpoint["webhook_url"]).to eq(create_params[:webhook_url])
            expect(kafka_messages.find { it[:topic] == "api_logs" }[:payload]).not_to include("whsec_")
          end
        end
      end
    end

    context "when the API log is produced" do
      before { allow(Utils::ApiLog).to receive(:produce) }

      it "filters secret_key from the API log response only" do
        subject

        expect(Utils::ApiLog).to have_received(:produce)
          .with(anything, anything, organization:, filtered_params: [], filtered_response: [:secret_key])
      end
    end

    context "when the organization uses the product catalog" do
      let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }

      %w[jwt hmac].each do |signature_algo|
        context "with the #{signature_algo} signature_algo" do
          let(:create_params) { super().merge(signature_algo:) }

          it "creates the endpoint" do
            subject

            expect(response).to have_http_status(:success)
            expect(json[:webhook_endpoint][:signature_algo]).to eq(signature_algo)
          end
        end
      end

      context "without a signature_algo" do
        let(:create_params) { super().except(:signature_algo) }

        it "signs with JWT" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:webhook_endpoint][:signature_algo]).to eq("jwt")
        end
      end
    end

    context "with event_types parameter provided" do
      context "when event_types is invalid" do
        let(:create_params) {
          {
            webhook_url: Faker::Internet.url,
            event_types: "wrong"
          }
        }

        it "returns unprocessable_content error" do
          subject

          expect(response).to have_http_status(:unprocessable_content)
          expect(json[:error_details]).to include(
            event_types: ["must_be_array"]
          )
        end
      end

      context "when event_types contains invalid types" do
        let(:create_params) {
          {
            webhook_url: Faker::Internet.url,
            event_types: ["wrong.type"]
          }
        }

        it "returns unprocessable_content error" do
          subject

          expect(response).to have_http_status(:unprocessable_content)
          expect(json[:error_details]).to include(
            event_types: ["contains invalid types: [\"wrong.type\"]"]
          )
        end
      end

      context "when event_types is [*]" do
        let(:create_params) {
          {
            webhook_url: Faker::Internet.url,
            event_types: ["*"]
          }
        }

        it "returns a success" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:webhook_endpoint][:webhook_url]).to eq(create_params[:webhook_url])
          expect(json[:webhook_endpoint][:event_types]).to eq(nil)
        end
      end
    end

    it_behaves_like "produces a security log", "webhook_endpoint.created" do
      before { subject }
    end
  end

  describe "GET /api/v1/webhook_endpoints" do
    subject { get_with_token(organization, "/api/v1/webhook_endpoints") }

    let(:organization) { create(:organization) }

    before { create_pair(:webhook_endpoint, organization:) }

    include_examples "requires API permission", "webhook_endpoint", "read"

    it "returns all webhook endpoints from organization" do
      subject

      expect(response).to have_http_status(:ok)
      expect(json[:meta][:total_count]).to eq(3)
    end

    context "with a standard_webhooks endpoint that has a signing key" do
      before do
        webhook_endpoint = create(:webhook_endpoint, organization:, signature_algo: :standard_webhooks)
        create(:webhook_endpoint_signing_key, webhook_endpoint:)
      end

      it "leaves signing_keys out of every item" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:webhook_endpoints].map { it.key?(:signing_keys) }.uniq).to eq([false])
        expect(response.body).not_to include("whsec_")
      end
    end
  end

  describe "GET /api/v1/webhook_endpoints/:id" do
    subject { get_with_token(organization, "/api/v1/webhook_endpoints/#{id}") }

    let(:webhook_endpoint) { create(:webhook_endpoint) }
    let(:organization) { webhook_endpoint.organization.reload }

    context "with existing id" do
      let(:id) { webhook_endpoint.id }

      include_examples "requires API permission", "webhook_endpoint", "read"

      it "returns the customer" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:webhook_endpoint][:lago_id]).to eq(webhook_endpoint.id)
        expect(json[:webhook_endpoint][:signing_keys]).to eq([])
      end

      context "with a standard_webhooks endpoint that has signing keys" do
        let(:webhook_endpoint) { create(:webhook_endpoint, signature_algo: :standard_webhooks) }
        let(:older_key) do
          travel_to(Time.zone.parse("2026-01-01 10:00:00")) { create(:webhook_endpoint_signing_key, webhook_endpoint:) }
        end
        let(:newer_key) do
          travel_to(Time.zone.parse("2026-02-01 10:00:00")) { create(:webhook_endpoint_signing_key, webhook_endpoint:) }
        end
        let(:expected_signing_keys) do
          [
            {lago_id: older_key.id, secret_key: older_key.secret, created_at: "2026-01-01T10:00:00Z"},
            {lago_id: newer_key.id, secret_key: newer_key.secret, created_at: "2026-02-01T10:00:00Z"}
          ]
        end

        before do
          newer_key
          older_key
        end

        it "returns the signing keys oldest first without the standard_webhooks_signature flag" do
          subject

          expect(response).to have_http_status(:ok)
          expect(organization.feature_flag_enabled?(:standard_webhooks_signature)).to be(false)
          expect(json[:webhook_endpoint][:signing_keys]).to eq(expected_signing_keys)
        end

        context "with the standard_webhooks_signature flag" do
          before { organization.enable_feature_flag!(:standard_webhooks_signature) }

          it "returns the signing keys oldest first" do
            subject

            expect(response).to have_http_status(:ok)
            expect(json[:webhook_endpoint][:signing_keys]).to eq(expected_signing_keys)
          end
        end

        context "when the organization has the api_permissions premium integration", :premium do
          let(:api_key) { organization.api_keys.first }

          before do
            organization.update!(premium_integrations: organization.premium_integrations.including("api_permissions"))
            api_key.update!(permissions: api_key.permissions.merge("webhook_endpoint" => modes))
          end

          context "when the API key can only read webhook endpoints" do
            let(:modes) { ["read"] }

            it "leaves signing_keys out" do
              subject

              expect(response).to have_http_status(:ok)
              expect(json[:webhook_endpoint][:lago_id]).to eq(webhook_endpoint.id)
              expect(json[:webhook_endpoint]).not_to have_key(:signing_keys)
              expect(response.body).not_to include("whsec_")
            end
          end

          context "when the API key can read and write webhook endpoints" do
            let(:modes) { ["read", "write"] }

            it "returns the signing keys" do
              subject

              expect(response).to have_http_status(:ok)
              expect(json[:webhook_endpoint][:signing_keys]).to eq(expected_signing_keys)
            end
          end
        end
      end
    end

    context "with not existing id" do
      let(:id) { SecureRandom.uuid }

      it "returns a not found error" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context "with an endpoint of another organization" do
      let(:other_webhook_endpoint) do
        create(:webhook_endpoint, organization: create(:organization), signature_algo: :standard_webhooks)
      end
      let(:id) { other_webhook_endpoint.id }

      before { create(:webhook_endpoint_signing_key, webhook_endpoint: other_webhook_endpoint) }

      it "returns a not found error without any signing key" do
        subject

        expect(response).to be_not_found_error("webhook_endpoint")
        expect(response.body).not_to include("whsec_")
      end
    end
  end

  describe "DELETE /api/v1webhook_endpoints/:id" do
    subject { delete_with_token(organization, "/api/v1/webhook_endpoints/#{id}") }

    include_context "with mocked security logger"

    let!(:webhook_endpoint) { create(:webhook_endpoint) }
    let(:organization) { webhook_endpoint.organization.reload }

    context "when webhook endpoint exists" do
      let(:id) { webhook_endpoint.id }

      include_examples "requires API permission", "webhook_endpoint", "write"

      it "deletes a webhook endpoint" do
        expect { subject }.to change(WebhookEndpoint, :count).by(-1)
      end

      it "returns deleted webhook_endpoint" do
        subject

        expect(response).to have_http_status(:success)

        expect(json[:webhook_endpoint][:lago_id]).to eq(webhook_endpoint.id)
        expect(json[:webhook_endpoint][:webhook_url]).to eq(webhook_endpoint.webhook_url)
        expect(json[:webhook_endpoint][:name]).to eq(webhook_endpoint.name)
        expect(json[:webhook_endpoint][:event_types]).to eq(webhook_endpoint.event_types)
      end

      context "with a standard_webhooks endpoint that has a signing key" do
        let(:webhook_endpoint) { create(:webhook_endpoint, signature_algo: :standard_webhooks) }

        before { create(:webhook_endpoint_signing_key, webhook_endpoint:) }

        it "leaves signing_keys out" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:webhook_endpoint]).not_to have_key(:signing_keys)
          expect(response.body).not_to include("whsec_")
        end

        context "when the API log is produced", :capture_kafka_messages do
          include_context "with API log infrastructure"

          it "logs the response without signing keys" do
            subject

            expect(response).to have_http_status(:success)
            logged_endpoint = api_log_payload["request_response"]["webhook_endpoint"]
            expect(logged_endpoint["lago_id"]).to eq(webhook_endpoint.id)
            expect(logged_endpoint).not_to have_key("signing_keys")
            expect(kafka_messages.find { it[:topic] == "api_logs" }[:payload]).not_to include("whsec_")
          end
        end
      end

      it_behaves_like "produces a security log", "webhook_endpoint.deleted" do
        before { subject }
      end
    end

    context "when webhook endpoint does not exist" do
      let(:id) { SecureRandom.uuid }

      it "returns not_found error" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "PUT /api/v1/webhook_endpoints/:id" do
    subject do
      put_with_token(
        organization,
        "/api/v1/webhook_endpoints/#{id}",
        {webhook_endpoint: update_params}
      )
    end

    include_context "with mocked security logger"

    let(:webhook_endpoint) { create(:webhook_endpoint) }
    let(:organization) { webhook_endpoint.organization.reload }
    let(:update_params) do
      {
        webhook_url: "http://foo.bar",
        signature_algo: "hmac",
        name: "Updated Webhook",
        event_types: ["invoice.created", "invoice.voided"]
      }
    end

    before { webhook_endpoint }

    context "when webhook endpoint exists" do
      let(:id) { webhook_endpoint.id }

      include_examples "requires API permission", "webhook_endpoint", "write"

      context "when all parameters are provided" do
        it "updates a webhook endpoint" do
          subject

          expect(response).to have_http_status(:success)

          expect(json[:webhook_endpoint][:webhook_url]).to eq("http://foo.bar")
          expect(json[:webhook_endpoint][:signature_algo]).to eq("hmac")
          expect(json[:webhook_endpoint][:name]).to eq("Updated Webhook")
          expect(json[:webhook_endpoint][:event_types]).to eq(["invoice.created", "invoice.voided"])
          expect(json[:webhook_endpoint][:signing_keys]).to eq([])
        end
      end

      context "when event_types is explicitly set to null" do
        let(:webhook_endpoint) { create(:webhook_endpoint, event_types: ["customer.created"]) }
        let(:update_params) { {event_types: nil} }

        it "updates a webhook endpoint" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:webhook_endpoint][:event_types]).to eq(nil)
        end
      end

      context "when event_types is explicitly set to empty array" do
        let(:webhook_endpoint) { create(:webhook_endpoint, event_types: ["customer.created"]) }
        let(:update_params) { {event_types: []} }

        it "updates a webhook endpoint" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:webhook_endpoint][:event_types]).to eq([])
        end
      end

      context "when event_types is invalid" do
        let(:update_params) { {event_types: "wrong"} }

        it "returns unprocessable_content error" do
          subject

          expect(response).to have_http_status(:unprocessable_content)
          expect(json[:error_details]).to include(
            event_types: ["must_be_array"]
          )
        end
      end

      context "when event_types contains invalid types" do
        let(:update_params) { {event_types: ["wrong.type"]} }

        it "returns unprocessable_content error" do
          subject

          expect(response).to have_http_status(:unprocessable_content)
          expect(json[:error_details]).to include(
            event_types: ["contains invalid types: [\"wrong.type\"]"]
          )
        end
      end

      context "when event_types is [*]" do
        let(:update_params) { {event_types: ["*"]} }

        it "returns a success" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:webhook_endpoint][:event_types]).to eq(nil)
        end
      end

      it_behaves_like "produces a security log", "webhook_endpoint.updated" do
        before { subject }
      end

      context "when switching to standard_webhooks" do
        let(:update_params) { {signature_algo: "standard_webhooks"} }

        it "returns a validation error without the standard_webhooks_signature flag" do
          expect { subject }.not_to change { webhook_endpoint.reload.attributes }

          expect(response).to have_http_status(:unprocessable_content)
          expect(json[:error_details]).to eq(signature_algo: ["value_is_invalid"])
        end

        context "with the standard_webhooks_signature flag" do
          before { organization.enable_feature_flag!(:standard_webhooks_signature) }

          it "updates the endpoint and creates exactly one signing key" do
            subject

            expect(response).to have_http_status(:success)
            expect(json[:webhook_endpoint][:signature_algo]).to eq("standard_webhooks")
            expect(webhook_endpoint.reload.signing_keys.count).to eq(1)
            signing_key = webhook_endpoint.signing_keys.sole
            expect(json[:webhook_endpoint][:signing_keys]).to eq(
              [{lago_id: signing_key.id, secret_key: signing_key.secret, created_at: signing_key.created_at.iso8601}]
            )
          end

          context "when the API log is produced", :capture_kafka_messages do
            include_context "with API log infrastructure"

            it "masks the secret_key of every signing key" do
              subject

              expect(response).to have_http_status(:success)
              signing_key = webhook_endpoint.signing_keys.sole
              logged_endpoint = api_log_payload["request_response"]["webhook_endpoint"]
              expect(logged_endpoint["signing_keys"]).to eq(
                [{"lago_id" => signing_key.id, "secret_key" => "[FILTERED]", "created_at" => signing_key.created_at.iso8601}]
              )
              expect(logged_endpoint["lago_id"]).to eq(webhook_endpoint.id)
              expect(logged_endpoint["webhook_url"]).to eq(webhook_endpoint.webhook_url)
              expect(kafka_messages.find { it[:topic] == "api_logs" }[:payload]).not_to include("whsec_")
            end
          end
        end
      end

      context "when switching a standard_webhooks endpoint back to jwt" do
        let(:webhook_endpoint) { create(:webhook_endpoint, signature_algo: :standard_webhooks) }
        let(:update_params) { {signature_algo: "jwt"} }

        before { create(:webhook_endpoint_signing_key, webhook_endpoint:) }

        it "returns an empty signing_keys list" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:webhook_endpoint][:signature_algo]).to eq("jwt")
          expect(webhook_endpoint.reload.signing_keys.count).to eq(1)
          expect(json[:webhook_endpoint][:signing_keys]).to eq([])
        end
      end

      context "when renaming a standard_webhooks endpoint of an organization without the flag" do
        let(:webhook_endpoint) { create(:webhook_endpoint, signature_algo: :standard_webhooks) }
        let(:update_params) { {name: "Renamed", signature_algo: "standard_webhooks"} }
        let(:signing_key) { create(:webhook_endpoint_signing_key, webhook_endpoint:) }

        before { signing_key }

        it "updates the endpoint and keeps its algorithm" do
          subject

          expect(json[:webhook_endpoint][:signing_keys]).to eq(
            [{lago_id: signing_key.id, secret_key: signing_key.secret, created_at: signing_key.created_at.iso8601}]
          )

          expect(response).to have_http_status(:success)
          expect(json[:webhook_endpoint][:name]).to eq("Renamed")
          expect(json[:webhook_endpoint][:signature_algo]).to eq("standard_webhooks")
          expect(webhook_endpoint.reload).to have_attributes(name: "Renamed", signature_algo: "standard_webhooks")
        end
      end

      context "when only webhook_url is provided" do
        let(:update_params) { {webhook_url: "http://foo.bar"} }

        it "updates webhook_url without resetting signature_algo" do
          subject

          expect(response).to have_http_status(:success)

          expect(json[:webhook_endpoint][:webhook_url]).to eq("http://foo.bar")
          expect(json[:webhook_endpoint][:signature_algo]).to eq("jwt")
        end
      end

      context "when only webhook_url is provided on a standard_webhooks endpoint without the flag" do
        let(:webhook_endpoint) { create(:webhook_endpoint, signature_algo: :standard_webhooks) }
        let(:update_params) { {webhook_url: "http://foo.bar"} }
        let(:signing_key) { create(:webhook_endpoint_signing_key, webhook_endpoint:) }

        before { signing_key }

        it "returns the signing keys" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:webhook_endpoint][:signature_algo]).to eq("standard_webhooks")
          expect(json[:webhook_endpoint][:signing_keys]).to eq(
            [{lago_id: signing_key.id, secret_key: signing_key.secret, created_at: signing_key.created_at.iso8601}]
          )
        end
      end
    end

    context "when webhook endpoint does not exist" do
      let(:id) { SecureRandom.uuid }

      it "returns not_found error" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context "with an endpoint of another organization" do
      let(:other_webhook_endpoint) do
        create(:webhook_endpoint, organization: create(:organization), signature_algo: :standard_webhooks)
      end
      let(:id) { other_webhook_endpoint.id }
      let(:update_params) { {name: "Renamed"} }

      before { create(:webhook_endpoint_signing_key, webhook_endpoint: other_webhook_endpoint) }

      it "returns a not found error without any signing key" do
        subject

        expect(response).to be_not_found_error("webhook_endpoint")
        expect(response.body).not_to include("whsec_")
        expect(other_webhook_endpoint.reload.name).not_to eq("Renamed")
      end
    end
  end
end
