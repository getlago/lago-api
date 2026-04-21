# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Quotes::ExecutionModeEnum do
  it "has the expected values" do
    expect(described_class.values.keys).to match_array(Quote::EXECUTION_MODES.keys.map(&:to_s))
  end
end
