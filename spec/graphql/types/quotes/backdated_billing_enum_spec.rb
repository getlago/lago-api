# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Quotes::BackdatedBillingEnum do
  it "has the expected values" do
    expect(described_class.values.keys).to match_array(Quote::BACKDATED_BILLING_OPTIONS.keys.map(&:to_s))
  end
end
