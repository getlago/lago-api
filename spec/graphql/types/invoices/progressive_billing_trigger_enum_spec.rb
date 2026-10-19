# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Invoices::ProgressiveBillingTriggerEnum do
  it "exposes the progressive billing triggers" do
    expect(described_class.values.keys).to match_array(%w[usage_threshold wallet_expiration])
  end
end
