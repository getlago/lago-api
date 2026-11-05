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
      end
    end

    context "with signature_algo hmac" do
      let(:create_params) { super().merge(signature_algo: "hmac") }

      it "creates the endpoint without the rollout flag" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:webhook_endpoint][:signature_algo]).to eq("hmac")
        expect(json[:webhook_endpoint]).not_to have_key(:signing_keys)
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

    context "with signature_algo standard_webhooks" do
      let(:create_params) { super().merge(signature_algo: "standard_webhooks") }

      it "returns unprocessable_content error without the rollout flag" do
        expect { subject }.not_to change(WebhookEndpoint, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(signature_algo: ["value_is_invalid"])
      end

      context "when the organization has the standard_webhooks_signature flag" do
        before { organization.enable_feature_flag!(:standard_webhooks_signature) }

        it "creates an endpoint signed with Standard Webhooks without rendering its signing keys" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:webhook_endpoint][:signature_algo]).to eq("standard_webhooks")
          expect(json[:webhook_endpoint]).not_to have_key(:signing_keys)
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

    context "with an endpoint signed with standard webhooks" do
      before { create(:webhook_endpoint, :standard_webhooks, organization:) }

      it "renders no signing keys" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:webhook_endpoints].map { it[:signature_algo] }).to include("standard_webhooks")
        expect(json[:webhook_endpoints].size).to eq(4)
        expect(json[:webhook_endpoints].flat_map(&:keys)).not_to include(:signing_keys)
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
        expect(json[:webhook_endpoint]).to include(lago_id: webhook_endpoint.id, signing_keys: [])
      end

      context "when the endpoint signs with standard webhooks" do
        let(:webhook_endpoint) { create(:webhook_endpoint, :standard_webhooks) }
        let(:signing_key) { webhook_endpoint.signing_keys.sole }

        before { organization.disable_feature_flag!(:standard_webhooks_signature) }

        it "returns its signing keys without the rollout flag" do
          subject

          expect(response).to have_http_status(:ok)
          expect(json[:webhook_endpoint][:signature_algo]).to eq("standard_webhooks")
          expect(json[:webhook_endpoint][:signing_keys]).to eq(
            [{lago_id: signing_key.id, secret_key: signing_key.secret_key, created_at: signing_key.created_at.iso8601}]
          )
          expect(signing_key.secret_key).to start_with("whsec_")
        end
      end

      context "when the API key can only read webhook endpoints", :premium do
        let(:webhook_endpoint) { create(:webhook_endpoint, :standard_webhooks) }

        before do
          organization.update!(premium_integrations: organization.premium_integrations.including("api_permissions"))
          api_key = organization.api_keys.first
          api_key.update!(permissions: api_key.permissions.merge("webhook_endpoint" => ["read"]))
        end

        it "returns the endpoint without its signing keys" do
          subject

          expect(response).to have_http_status(:ok)
          expect(json[:webhook_endpoint]).to include(lago_id: webhook_endpoint.id, signature_algo: "standard_webhooks")
          expect(json[:webhook_endpoint]).not_to have_key(:signing_keys)
        end
      end

      context "when the endpoint signs with jwt and kept a secret from standard webhooks" do
        let(:webhook_endpoint) { create(:webhook_endpoint, signature_algo: :jwt, name: "Billing events", event_types: ["customer.created"]) }

        before { create(:webhook_endpoint_signing_key, webhook_endpoint:) }

        it "returns no signing keys and its other fields unchanged" do
          subject

          expect(response).to have_http_status(:ok)
          expect(json[:webhook_endpoint]).to eq(
            lago_id: webhook_endpoint.id,
            lago_organization_id: webhook_endpoint.organization_id,
            webhook_url: webhook_endpoint.webhook_url,
            signature_algo: "jwt",
            name: "Billing events",
            event_types: ["customer.created"],
            created_at: webhook_endpoint.created_at.iso8601,
            signing_keys: []
          )
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

      it_behaves_like "produces a security log", "webhook_endpoint.deleted" do
        before { subject }
      end

      context "when the endpoint signs with standard webhooks" do
        let!(:webhook_endpoint) { create(:webhook_endpoint, :standard_webhooks) }

        it "renders no signing keys" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:webhook_endpoint][:signature_algo]).to eq("standard_webhooks")
          expect(json[:webhook_endpoint]).not_to have_key(:signing_keys)
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
          expect(json[:webhook_endpoint]).not_to have_key(:signing_keys)
          expect(json[:webhook_endpoint][:name]).to eq("Updated Webhook")
          expect(json[:webhook_endpoint][:event_types]).to eq(["invoice.created", "invoice.voided"])
        end
      end

      context "when switching to standard_webhooks" do
        let(:update_params) { super().merge(signature_algo: "standard_webhooks") }

        it "returns unprocessable_content error without the rollout flag" do
          expect { subject }.not_to change { webhook_endpoint.reload.attributes }

          expect(response).to have_http_status(:unprocessable_content)
          expect(json[:error_details]).to eq(signature_algo: ["value_is_invalid"])
        end

        context "when the organization has the standard_webhooks_signature flag" do
          before { organization.enable_feature_flag!(:standard_webhooks_signature) }

          it "switches the endpoint to Standard Webhooks without rendering its signing keys" do
            subject

            expect(response).to have_http_status(:success)
            expect(json[:webhook_endpoint][:signature_algo]).to eq("standard_webhooks")
            expect(json[:webhook_endpoint]).not_to have_key(:signing_keys)
          end
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

      context "when only webhook_url is provided" do
        let(:update_params) { {webhook_url: "http://foo.bar"} }

        it "updates webhook_url without resetting signature_algo" do
          subject

          expect(response).to have_http_status(:success)

          expect(json[:webhook_endpoint][:webhook_url]).to eq("http://foo.bar")
          expect(json[:webhook_endpoint][:signature_algo]).to eq("jwt")
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
  end
end
