# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::CopyToProduction::ItemTypeEnum do
  it "enumerates the item types" do
    expect(described_class.values.keys).to eq(%w[billable_metric feature])
  end
end
