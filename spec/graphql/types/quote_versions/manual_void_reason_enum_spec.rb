# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::QuoteVersions::ManualVoidReasonEnum do
  it "enumerizes only the manual void reasons" do
    expect(described_class.values.keys).to match_array(%w[manual superseded])
  end
end
