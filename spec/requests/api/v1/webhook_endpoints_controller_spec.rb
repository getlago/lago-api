# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::WebhookEndpointsController do
  describe "POST /api/v1/webhook_endpoints" do
    subject do
      post_with_token(
        organization,
        "/api/v1/webhook_endpoints",
        {webhook_endpoint: create_params}
      )
    end

    let(:organization) { create(:organization) }
    let(:create_params) do
      {
        webhook_url: Faker::Internet.url,
        signature_algo: "jwt"
      }
    end

    include_context "with mocked security logger"
    include_examples "requires API permission", "webhook_endpoint", "write"

    it "returns a success" do
      subject

      expect(response).to have_http_status(:success)

      expect(json[:webhook_endpoint][:webhook_url]).to eq(create_params[:webhook_url])
      expect(json[:webhook_endpoint][:signature_algo]).to eq("jwt")
    end

    it "produces a security log" do
      subject

      expect(security_logger).to have_received(:produce).with(
        organization: organization,
        log_type: "webhook_endpoint",
        log_event: "webhook_endpoint.created",
        resources: {webhook_url: create_params[:webhook_url], signature_algo: "jwt"}
      )
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
      end

      it "produces a security log" do
        subject

        expect(security_logger).to have_received(:produce).with(
          organization: organization,
          log_type: "webhook_endpoint",
          log_event: "webhook_endpoint.deleted",
          resources: {webhook_url: webhook_endpoint.webhook_url, signature_algo: "jwt"}
        )
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
        signature_algo: "hmac"
      }
    end

    before { webhook_endpoint }

    context "when webhook endpoint exists" do
      let(:id) { webhook_endpoint.id }

      include_examples "requires API permission", "webhook_endpoint", "write"

      it "updates a webhook endpoint" do
        subject

        expect(response).to have_http_status(:success)

        expect(json[:webhook_endpoint][:webhook_url]).to eq("http://foo.bar")
        expect(json[:webhook_endpoint][:signature_algo]).to eq("hmac")
      end

      it "produces a security log" do
        subject

        expect(security_logger).to have_received(:produce).with(
          organization: organization,
          log_type: "webhook_endpoint",
          log_event: "webhook_endpoint.updated",
          resources: {
            webhook_url: {deleted: webhook_endpoint.webhook_url, added: "http://foo.bar"},
            signature_algo: {deleted: "jwt", added: "hmac"}
          }
        )
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
