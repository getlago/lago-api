# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::WebhookEndpointsController do
  include_context "with mocked security logger"

  # Without the endpoint the organization factory creates, so that each example lists only its own.
  let_it_be(:organization, refind: true) { create_default(:organization, webhook_url: nil) }

  let(:invalid_algorithm_details) do
    [{code: "value_is_invalid", field: "signature_algo", meta: {allowed_values: %w[standard_webhooks]}}]
  end

  describe "POST /api/v2/webhook_endpoints" do
    subject(:request) { post_with_token(organization, "/api/v2/webhook_endpoints#{query}", {webhook_endpoint: create_params}) }

    let(:query) { "" }
    let(:create_params) do
      {
        webhook_url: "https://example.com/webhooks",
        name: "Billing events",
        event_types: ["customer.created", "invoice.created"]
      }
    end

    include_examples "requires API permission", "webhook_endpoint", "write"

    it "creates a webhook endpoint signed with standard webhooks by default, without rendering its secret" do
      expect { request }.to change(organization.webhook_endpoints, :count).by(1)

      expect(response).to have_http_status(:ok)
      webhook_endpoint = organization.webhook_endpoints.sole
      expect(webhook_endpoint).to have_attributes(
        webhook_url: "https://example.com/webhooks",
        signature_algo: "standard_webhooks",
        name: "Billing events",
        event_types: ["customer.created", "invoice.created"]
      )
      expect(webhook_endpoint.signing_keys.count).to eq(1)
      expect(json[:webhook_endpoint]).to eq(
        lago_id: webhook_endpoint.id,
        name: "Billing events",
        webhook_url: "https://example.com/webhooks",
        signature_algo: "standard_webhooks",
        event_types: ["customer.created", "invoice.created"],
        created_at: webhook_endpoint.created_at.iso8601(6),
        updated_at: webhook_endpoint.updated_at.iso8601(6)
      )
      expect(response.headers["X-Lago-Endpoint-Status"]).to eq("beta")
    end

    it_behaves_like "produces a security log", "webhook_endpoint.created" do
      before { request }
    end

    [["standard_webhooks", "standard_webhooks"], ["a null", nil]].each do |label, value|
      context "with #{label} signature_algo" do
        let(:create_params) { super().merge(signature_algo: value) }

        it "creates the endpoint signed with standard webhooks, with one secret" do
          expect { request }.to change(WebhookEndpointSigningKey, :count).by(1)

          expect(response).to have_http_status(:ok)
          expect(json[:webhook_endpoint][:signature_algo]).to eq("standard_webhooks")
        end
      end
    end

    context "with expands[]=signing_keys" do
      let(:query) { "?expands[]=signing_keys" }

      it "creates nothing, as only show renders the signing keys" do
        expect { request }.not_to change(WebhookEndpoint, :count)

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(
          code: "expand_not_supported",
          details: [{code: "action_not_expandable", field: "expands", meta: {invalid_values: ["signing_keys"]}}]
        )
      end
    end

    [["jwt", "jwt"], ["hmac", "hmac"], ["an unknown", "md5"], ["a false", false]].each do |label, value|
      context "with #{label} signature_algo" do
        let(:create_params) { super().merge(signature_algo: value) }

        it "returns a validation error with the allowed values, without creating the endpoint" do
          expect { request }.not_to change(WebhookEndpoint, :count)

          expect(response).to have_http_status(:unprocessable_content)
          expect(json).to eq(code: "validation_errors", details: invalid_algorithm_details)
        end
      end
    end

    context "with event_types [*]" do
      let(:create_params) { super().merge(event_types: ["*"]) }

      it "sends every event type" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:webhook_endpoint][:event_types]).to be_nil
      end
    end

    context "with a scalar event_types" do
      let(:create_params) { super().merge(event_types: "customer.created") }

      it "returns a validation error rather than ignoring it" do
        request

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(
          code: "validation_errors",
          details: [{code: "must_be_array", field: "event_types", meta: {}}]
        )
      end
    end

    context "with an unknown event type" do
      let(:create_params) { super().merge(event_types: ["wrong.type"]) }

      it "returns a token, not the sentence v1 renders" do
        request

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(
          code: "validation_errors",
          details: [{code: "value_is_invalid", field: "event_types", meta: {}}]
        )
      end
    end

    context "with an invalid webhook_url" do
      let(:create_params) { super().merge(webhook_url: "not a url") }

      it "returns a validation error on webhook_url" do
        request

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(
          code: "validation_errors",
          details: [{code: "url_is_invalid", field: "webhook_url", meta: {}}]
        )
      end
    end

    context "when the webhook_url is already used" do
      before { create(:webhook_endpoint, :legacy_signature_algo, organization:, webhook_url: create_params[:webhook_url]) }

      it "returns a validation error on webhook_url" do
        request

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:details]).to eq([{code: "value_already_exist", field: "webhook_url", meta: {}}])
      end
    end

    context "when the organization has reached the endpoint limit" do
      before { create_list(:webhook_endpoint, WebhookEndpoint::LIMIT, :legacy_signature_algo, organization:) }

      it "returns a token, not the sentence v1 renders" do
        expect { request }.not_to change(WebhookEndpoint, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(
          code: "validation_errors",
          details: [{code: "exceeded_limit", field: "base", meta: {}}]
        )
      end
    end

    context "when the webhook_endpoint wrapper is missing" do
      subject(:request) { post_with_token(organization, "/api/v2/webhook_endpoints", create_params) }

      it "returns the v2 missing parameter error" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(
          code: "missing_parameter",
          details: [{code: "missing", field: "webhook_endpoint", meta: {}}]
        )
      end
    end

    context "when the webhook_endpoint wrapper is not an object" do
      subject(:request) { post_with_token(organization, "/api/v2/webhook_endpoints", {webhook_endpoint: "https://example.com"}) }

      it "returns the v2 missing parameter error" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("missing_parameter")
      end
    end
  end

  %i[put patch].each do |http_method|
    describe "#{http_method.upcase} /api/v2/webhook_endpoints/:id" do
      subject(:request) do
        public_send(:"#{http_method}_with_token", organization, "/api/v2/webhook_endpoints/#{webhook_endpoint.id}#{query}", {webhook_endpoint: update_params})
      end

      let(:query) { "" }
      # A jwt endpoint created before the organization had the product catalog.
      let(:webhook_endpoint) do
        create(:webhook_endpoint, :legacy_signature_algo, organization:, signature_algo: :jwt, event_types: ["customer.created"])
      end
      let(:update_params) do
        {
          webhook_url: "https://example.com/updated",
          signature_algo: "standard_webhooks",
          name: "Renamed",
          event_types: ["invoice.created"]
        }
      end

      include_examples "requires API permission", "webhook_endpoint", "write"

      it "updates the webhook endpoint and switches it to standard webhooks with one secret" do
        request

        expect(response).to have_http_status(:ok)
        expect(webhook_endpoint.reload).to have_attributes(
          webhook_url: "https://example.com/updated",
          signature_algo: "standard_webhooks",
          name: "Renamed",
          event_types: ["invoice.created"]
        )
        expect(webhook_endpoint.signing_keys.count).to eq(1)
        expect(json[:webhook_endpoint]).to eq(
          lago_id: webhook_endpoint.id,
          name: "Renamed",
          webhook_url: "https://example.com/updated",
          signature_algo: "standard_webhooks",
          event_types: ["invoice.created"],
          created_at: webhook_endpoint.created_at.iso8601(6),
          updated_at: webhook_endpoint.updated_at.iso8601(6)
        )
      end

      it_behaves_like "produces a security log", "webhook_endpoint.updated" do
        before { request }
      end

      context "when the endpoint already signs with standard webhooks" do
        let(:webhook_endpoint) { create(:webhook_endpoint, :standard_webhooks, organization:) }

        it "updates it and keeps its secret" do
          signing_key_id = webhook_endpoint.signing_keys.sole.id

          request

          expect(response).to have_http_status(:ok)
          expect(webhook_endpoint.reload).to have_attributes(webhook_url: "https://example.com/updated", name: "Renamed")
          expect(webhook_endpoint.signing_keys.pluck(:id)).to eq([signing_key_id])
        end
      end

      context "with only a webhook_url" do
        let(:update_params) { {webhook_url: "https://example.com/updated"} }

        it "keeps the other attributes, the jwt algorithm included, without a secret" do
          request

          expect(response).to have_http_status(:ok)
          expect(webhook_endpoint.reload).to have_attributes(
            webhook_url: "https://example.com/updated",
            signature_algo: "jwt",
            name: nil,
            event_types: ["customer.created"]
          )
          expect(webhook_endpoint.signing_keys).to be_empty
          expect(json[:webhook_endpoint][:signature_algo]).to eq("jwt")
        end
      end

      context "with its current jwt signature_algo" do
        let(:update_params) { {name: "Renamed", signature_algo: "jwt"} }

        it "keeps the algorithm the organization no longer allows" do
          request

          expect(response).to have_http_status(:ok)
          expect(webhook_endpoint.reload).to have_attributes(signature_algo: "jwt", name: "Renamed")
        end
      end

      context "with only a name" do
        let(:update_params) { {name: "Renamed"} }

        it "keeps the url" do
          url = webhook_endpoint.webhook_url

          request

          expect(response).to have_http_status(:ok)
          expect(webhook_endpoint.reload).to have_attributes(webhook_url: url, signature_algo: "jwt", name: "Renamed")
        end
      end

      [["hmac", "hmac"], ["an unknown", "md5"], ["a null", nil]].each do |label, value|
        context "with #{label} signature_algo" do
          let(:update_params) { {signature_algo: value} }

          it "returns a validation error without changing the endpoint" do
            expect { request }.not_to change { webhook_endpoint.reload.attributes }

            expect(response).to have_http_status(:unprocessable_content)
            expect(json).to eq(code: "validation_errors", details: invalid_algorithm_details)
            expect(webhook_endpoint.signing_keys).to be_empty
          end
        end
      end

      context "when the webhook_url is used by another endpoint" do
        let(:update_params) { {webhook_url: other.webhook_url} }
        let(:other) { create(:webhook_endpoint, :standard_webhooks, organization:) }

        it "returns a validation error on webhook_url" do
          request

          expect(response).to have_http_status(:unprocessable_content)
          expect(json[:details]).to eq([{code: "value_already_exist", field: "webhook_url", meta: {}}])
        end
      end

      context "with expands[]=signing_keys" do
        let(:query) { "?expands[]=signing_keys" }

        it "changes nothing, as only show renders the signing keys" do
          expect { request }.not_to change { webhook_endpoint.reload.attributes }

          expect(response).to have_http_status(:bad_request)
          expect(json[:code]).to eq("expand_not_supported")
          expect(webhook_endpoint.signing_keys).to be_empty
        end
      end

      context "with event_types null" do
        let(:update_params) { {event_types: nil} }

        it "sends every event type" do
          request

          expect(response).to have_http_status(:ok)
          expect(webhook_endpoint.reload.event_types).to be_nil
        end
      end

      context "with an unknown event type" do
        let(:update_params) { {event_types: ["wrong.type"]} }

        it "returns a token, not the sentence v1 renders" do
          request

          expect(response).to have_http_status(:unprocessable_content)
          expect(json[:details]).to eq([{code: "value_is_invalid", field: "event_types", meta: {}}])
        end
      end

      context "when the webhook endpoint does not exist" do
        let(:webhook_endpoint) { build_stubbed(:webhook_endpoint) }

        it "returns a not found error" do
          request

          expect(response).to be_v2_not_found_error("webhook_endpoint")
        end
      end

      context "when the webhook endpoint does not exist and the signature_algo is unknown" do
        let(:webhook_endpoint) { build_stubbed(:webhook_endpoint) }
        let(:update_params) { {signature_algo: "md5"} }

        it "returns a not found error before validating the input" do
          request

          expect(response).to be_v2_not_found_error("webhook_endpoint")
        end
      end

      context "when the webhook endpoint belongs to another organization" do
        let(:webhook_endpoint) { create(:webhook_endpoint, organization: create(:organization)) }

        it "does not update the foreign endpoint" do
          expect { request }.not_to change { webhook_endpoint.reload.attributes }

          expect(response).to be_v2_not_found_error("webhook_endpoint")
        end
      end
    end
  end

  describe "GET /api/v2/webhook_endpoints/:id" do
    subject(:request) { get_with_token(organization, "/api/v2/webhook_endpoints/#{webhook_endpoint.id}", params) }

    let(:params) { {} }
    let(:webhook_endpoint) do
      create(:webhook_endpoint, :legacy_signature_algo, organization:, name: "Billing events", signature_algo: :hmac, event_types: ["customer.created"])
    end

    include_examples "requires API permission", "webhook_endpoint", "read"

    it "returns the webhook endpoint without its signing keys" do
      request

      expect(response).to have_http_status(:ok)
      expect(json[:webhook_endpoint]).to eq(
        lago_id: webhook_endpoint.id,
        name: "Billing events",
        webhook_url: webhook_endpoint.webhook_url,
        signature_algo: "hmac",
        event_types: ["customer.created"],
        created_at: webhook_endpoint.created_at.iso8601(6),
        updated_at: webhook_endpoint.updated_at.iso8601(6)
      )
    end

    context "with expands[]=signing_keys" do
      let(:params) { {expands: %w[signing_keys]} }

      context "when the endpoint signs with standard webhooks" do
        let(:webhook_endpoint) { create(:webhook_endpoint, :standard_webhooks, organization:) }
        let(:signing_key) { webhook_endpoint.signing_keys.sole }

        it "returns its secret, stored encrypted" do
          request

          expect(response).to have_http_status(:ok)
          expect(json[:webhook_endpoint][:signing_keys]).to eq(
            [{lago_id: signing_key.id, secret_key: signing_key.secret_key, created_at: signing_key.created_at.iso8601(6)}]
          )
          expect(signing_key.secret_key).to start_with("whsec_")
          expect(signing_key.ciphertext_for(:secret_key)).not_to include(signing_key.secret_key)
        end
      end

      %i[jwt hmac].each do |algo|
        context "when the endpoint signs with #{algo}" do
          let(:webhook_endpoint) { create(:webhook_endpoint, :legacy_signature_algo, organization:, signature_algo: algo) }

          it "returns no secret" do
            request

            expect(response).to have_http_status(:ok)
            expect(json[:webhook_endpoint][:signature_algo]).to eq(algo.to_s)
            expect(json[:webhook_endpoint][:signing_keys]).to eq([])
          end
        end
      end

      context "when a jwt endpoint kept a secret from standard webhooks" do
        let(:webhook_endpoint) { create(:webhook_endpoint, :legacy_signature_algo, organization:, signature_algo: :jwt) }

        before { create(:webhook_endpoint_signing_key, webhook_endpoint:) }

        it "returns no secret" do
          request

          expect(response).to have_http_status(:ok)
          expect(json[:webhook_endpoint][:signing_keys]).to eq([])
        end
      end

      context "when the API key can only read webhook endpoints", :premium do
        let(:webhook_endpoint) { create(:webhook_endpoint, :standard_webhooks, organization:) }

        before do
          organization.update!(premium_integrations: organization.premium_integrations.including("api_permissions"))
          api_key = organization.api_keys.first
          api_key.update!(permissions: api_key.permissions.merge("webhook_endpoint" => ["read"]))
        end

        it "refuses the expansion" do
          request

          expect(response).to have_http_status(:forbidden)
          expect(json).to eq(code: "write_action_not_allowed_for_webhook_endpoint", details: [])
        end
      end
    end

    context "when the webhook endpoint does not exist" do
      let(:webhook_endpoint) { build_stubbed(:webhook_endpoint) }

      it "returns a not found error" do
        request

        expect(response).to be_v2_not_found_error("webhook_endpoint")
      end
    end

    context "when the webhook endpoint belongs to another organization" do
      let(:webhook_endpoint) { create(:webhook_endpoint, organization: create(:organization)) }

      it "does not expose the foreign endpoint" do
        request

        expect(response).to be_v2_not_found_error("webhook_endpoint")
      end
    end

    context "with an unknown expansion" do
      let(:params) { {expands: ["webhooks"]} }

      it "rejects it and lists the allowed expansions" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(
          code: "invalid_expand",
          details: [{code: "invalid_expand", field: "expands", meta: {invalid_values: ["webhooks"], allowed_values: ["signing_keys"]}}]
        )
      end
    end
  end

  describe "GET /api/v2/webhook_endpoints" do
    subject(:request) { get_with_token(organization, "/api/v2/webhook_endpoints", {limit: 1}) }

    let(:newest) { create(:webhook_endpoint, :standard_webhooks, organization:, created_at: 1.day.ago) }

    before do
      create(:webhook_endpoint, :legacy_signature_algo, organization:, created_at: 2.days.ago)
      newest
      create(:webhook_endpoint, organization: create(:organization))
    end

    include_examples "requires API permission", "webhook_endpoint", "read"

    it "returns the newest webhook endpoint and a cursor, excluding foreign ones" do
      request

      expect(response).to have_http_status(:ok)
      expect(json[:webhook_endpoints].pluck(:lago_id)).to eq([newest.id])
      expect(json[:webhook_endpoints].first.keys).to match_array(%i[lago_id name webhook_url signature_algo event_types created_at updated_at])
      expect(json[:meta][:next_cursor]).to be_present
      expect(json[:meta][:prev_cursor]).to be_nil
    end

    it_behaves_like "a cursor paginated v2 endpoint", collection: :webhook_endpoints, model: WebhookEndpoint do
      let(:paginated_path) { "/api/v2/webhook_endpoints" }
      let(:create_paginated_record) { ->(created_at) { create(:webhook_endpoint, :standard_webhooks, organization:, created_at:) } }
    end

    it_behaves_like "a v2 list filtered on created_at", collection: :webhook_endpoints do
      let(:filtered_path) { "/api/v2/webhook_endpoints" }
      let(:create_filtered_record) { ->(created_at) { create(:webhook_endpoint, :standard_webhooks, organization:, created_at:) } }
    end
  end

  describe "DELETE /api/v2/webhook_endpoints/:id" do
    subject(:request) { delete_with_token(organization, "/api/v2/webhook_endpoints/#{webhook_endpoint.id}#{query}") }

    let(:query) { "" }
    let(:webhook_endpoint) { create(:webhook_endpoint, :standard_webhooks, organization:) }

    before { webhook_endpoint }

    include_examples "requires API permission", "webhook_endpoint", "write"

    it "deletes the webhook endpoint and its signing keys and returns it" do
      expect { request }.to change(WebhookEndpoint, :count).by(-1)
        .and change(WebhookEndpointSigningKey, :count).by(-1)

      expect(response).to have_http_status(:ok)
      expect(json[:webhook_endpoint][:lago_id]).to eq(webhook_endpoint.id)
      expect(json[:webhook_endpoint].keys).not_to include(:signing_keys)
    end

    it_behaves_like "produces a security log", "webhook_endpoint.deleted" do
      before { request }
    end

    context "with expands[]=signing_keys" do
      let(:query) { "?expands[]=signing_keys" }

      it "deletes nothing, as only show renders the signing keys" do
        expect { request }.not_to change(WebhookEndpoint, :count)

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("expand_not_supported")
      end
    end

    context "when the webhook endpoint does not exist" do
      let(:webhook_endpoint) { build_stubbed(:webhook_endpoint) }

      it "returns a not found error" do
        request

        expect(response).to be_v2_not_found_error("webhook_endpoint")
      end
    end

    context "when the webhook endpoint belongs to another organization" do
      let(:webhook_endpoint) { create(:webhook_endpoint, organization: create(:organization)) }

      it "does not delete the foreign endpoint" do
        expect { request }.not_to change(WebhookEndpoint, :count)

        expect(response).to be_v2_not_found_error("webhook_endpoint")
      end
    end
  end

  describe "when the product catalog is disabled", product_catalog: false do
    let(:webhook_endpoint) { create(:webhook_endpoint, organization:) }

    before { webhook_endpoint }

    [
      [:get, "/api/v2/webhook_endpoints"],
      [:post, "/api/v2/webhook_endpoints"],
      [:get, "/api/v2/webhook_endpoints/:id"],
      [:put, "/api/v2/webhook_endpoints/:id"],
      [:delete, "/api/v2/webhook_endpoints/:id"]
    ].each do |http_method, path|
      context "when using #{http_method.upcase} #{path}" do
        subject(:request) do
          public_send(
            :"#{http_method}_with_token",
            organization,
            path.sub(":id", webhook_endpoint.id),
            {limit: 0, webhook_endpoint: {webhook_url: "https://example.com/changed"}}
          )
        end

        it "checks the feature before pagination or writes" do
          expect { request }.not_to change { webhook_endpoint.reload.attributes }

          expect(response).to have_http_status(:forbidden)
          expect(json[:code]).to eq("feature_unavailable")
        end
      end
    end
  end
end
