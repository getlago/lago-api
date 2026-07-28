# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Paystack::HandleIncomingWebhookService do
  subject(:result) { described_class.call(inbound_webhook:) }

  let(:organization) { create(:organization) }
  let(:code) { "paystack_live" }
  let(:payment_provider) { create(:paystack_provider, organization:, code:) }
  let(:payload) { {"event" => "charge.success", "data" => {"reference" => "lago-ref"}} }
  let(:inbound_webhook) { create(:inbound_webhook, source: :paystack, organization:, code:, payload:) }

  before { payment_provider }

  it "enqueues the Paystack event handler" do
    expect(result).to be_success
    expect(PaymentProviders::Paystack::HandleEventJob).to have_been_enqueued.with(
      organization.id,
      payment_provider.id,
      payload
    )
  end

  context "when the provider cannot be found" do
    let(:inbound_webhook) { create(:inbound_webhook, source: :paystack, organization:, code: "missing", payload:) }

    it "returns a webhook error" do
      expect(result).not_to be_success
      expect(result.error.code).to eq("webhook_error")
      expect(result.error.error_message).to eq("Payment provider not found")
    end
  end
end
