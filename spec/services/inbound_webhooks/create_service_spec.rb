# frozen_string_literal: true

require "rails_helper"

RSpec.describe InboundWebhooks::CreateService, type: :service do
  subject(:result) do
    described_class.call(
      organization_id: organization.id,
      webhook_source:,
      code:,
      payload:,
      signature:,
      event_type:
    )
  end

  let(:organization) { create :organization }
  let(:code) { "stripe_1" }
  let(:webhook_source) { "stripe" }
  let(:signature) { "signature" }
  let(:payload) { event.merge(code:).to_json }
  let(:event_type) { "payment_intent.successful" }

  let(:event) do
    path = Rails.root.join("spec/fixtures/stripe/payment_intent_event.json")
    JSON.parse(File.read(path))
  end

  it "creates an inbound webhook" do
    expect { result }.to change(InboundWebhook, :count).by(1)
  end

  it "returns a pending inbound webhook in the result" do
    expect(result.inbound_webhook).to be_a(InboundWebhook)
    expect(result.inbound_webhook).to be_pending
  end

  it "queues an InboundWebhook::ProcessJob job" do
    result

    expect(InboundWebhooks::ProcessJob)
      .to have_been_enqueued
      .with(inbound_webhook: result.inbound_webhook)
  end

  context "with validation error" do
    let(:webhook_source) { nil }

    it "returns an error" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(result.error.messages[:source]).to eq(["value_is_mandatory"])
    end

    it "does not queue an InboundWebhook::ProcessJob job" do
      result

      expect(InboundWebhooks::ProcessJob).not_to have_been_enqueued
    end
  end
end
