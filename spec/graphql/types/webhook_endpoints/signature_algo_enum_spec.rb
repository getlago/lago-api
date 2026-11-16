# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::WebhookEndpoints::SignatureAlgoEnum do
  it "exposes every signature algorithm" do
    expect(described_class.values.keys).to match_array(%w[jwt hmac standard_webhooks])
  end
end
