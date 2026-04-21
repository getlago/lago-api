# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Quotes::VoidReasonEnum do
  it "has the expected values" do
    expect(described_class.values.keys).to match_array(Quote::VOID_REASONS.keys.map(&:to_s))
  end
end
