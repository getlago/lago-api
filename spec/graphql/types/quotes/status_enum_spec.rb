# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Quotes::StatusEnum do
  it "has the expected values" do
    expect(described_class.values.keys).to match_array(Quote::STATUSES.keys.map(&:to_s))
  end
end
