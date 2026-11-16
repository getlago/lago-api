# frozen_string_literal: true

require "rails_helper"

describe "Standard Webhooks signature" do
  let(:organization) { create(:organization, webhook_url: nil, feature_flags: ["standard_webhooks_signature"]) }
  let(:webhook_url) { "https://example.com/lago-webhooks" }
  let(:requests_sent) { [] }

  # Headers Net::HTTP adds to every request, whatever the signature algorithm.
  let(:transport_headers) { %w[content-type accept user-agent accept-encoding host content-length] }

  before do
    stub_request(:post, webhook_url)
      .with do |req|
        requests_sent << {headers: req.headers.transform_keys(&:downcase), body: req.body}
        true
      end
      .to_return({status: 500}, {status: 200})
  end

  # Computed with OpenSSL over the bytes sent, without the signing code of Lago.
  def expected_signature(secret:, id:, timestamp:, body:)
    key = Base64.strict_decode64(secret.delete_prefix("whsec_"))
    "v1," + Base64.strict_encode64(OpenSSL::HMAC.digest("sha256", key, "#{id}.#{timestamp}.#{body}"))
  end

  it "signs the delivery and its retry with the endpoint signing key" do
    travel_to(Time.zone.parse("2026-11-06T10:00:00Z")) do
      api_call do
        post_with_token(
          organization,
          "/api/v1/webhook_endpoints",
          {webhook_endpoint: {webhook_url:, signature_algo: "standard_webhooks"}}
        )
      end
    end

    webhook_endpoint = organization.webhook_endpoints.sole
    expect(webhook_endpoint).to be_standard_webhooks
    secret = webhook_endpoint.signing_keys.sole.secret

    travel_to(Time.zone.parse("2026-11-06T10:00:00Z")) do
      create_or_update_customer({external_id: "cust_1"}, perform_jobs: false)
      # Runs SendWebhookJob, which enqueues the first delivery.
      perform_all_enqueued_jobs(except: [SendHttpWebhookJob])
      perform_enqueued_jobs(only: SendHttpWebhookJob)
    end

    webhook = Webhook.sole
    expect(webhook.webhook_type).to eq("customer.created")
    expect(webhook).to be_retrying
    expect(requests_sent.size).to eq(1)

    first = requests_sent.first
    first_timestamp = Time.zone.parse("2026-11-06T10:00:00Z").to_i.to_s
    expect(first[:headers].keys - transport_headers).to match_array(%w[webhook-id webhook-timestamp webhook-signature])
    expect(first[:headers]["webhook-id"]).to eq(webhook.id)
    expect(first[:headers]["webhook-timestamp"]).to eq(first_timestamp)
    expect(first[:headers]["webhook-signature"]).to eq(
      expected_signature(secret:, id: webhook.id, timestamp: first_timestamp, body: first[:body])
    )
    expect(JSON.parse(first[:body])["webhook_type"]).to eq("customer.created")

    expect(SendHttpWebhookJob).to have_been_enqueued.with(webhook)

    travel_to(Time.zone.parse("2026-11-06T10:10:00Z")) do
      perform_enqueued_jobs(only: SendHttpWebhookJob)
    end

    expect(requests_sent.size).to eq(2)

    retry_request = requests_sent.second
    retry_timestamp = Time.zone.parse("2026-11-06T10:10:00Z").to_i.to_s
    expect(retry_request[:headers].keys - transport_headers).to match_array(%w[webhook-id webhook-timestamp webhook-signature])
    expect(retry_request[:headers]["webhook-id"]).to eq(webhook.id)
    expect(retry_request[:headers]["webhook-timestamp"]).to eq(retry_timestamp)
    expect(retry_request[:headers]["webhook-signature"]).to eq(
      expected_signature(secret:, id: webhook.id, timestamp: retry_timestamp, body: retry_request[:body])
    )
    expect(retry_request[:body]).to eq(first[:body])
    expect(webhook.reload).to be_succeeded
  end
end
