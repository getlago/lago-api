# frozen_string_literal: true

require "spec_helper"
require_relative "../../billing_matrix/run"

RSpec.describe BillingMatrix::CLI do
  let(:rows) do
    %w[smoke/first interactions/first smoke/second smoke/third].map do |id|
      BillingMatrix::Row.new({"id" => id, "area" => id.split("/").first}, source: "example.yml")
    end
  end

  it "intersects repeated id filters with the area filter" do
    options = described_class.parse(%w[--id smoke/first --id interactions/first --area smoke])
    expect(described_class.new(options).send(:select, rows).map(&:id)).to eq(["smoke/first"])
  end

  it "partitions selected rows without overlaps or omissions" do
    selected = (1..2).map do |index|
      options = described_class.parse(["--area", "smoke", "--shard", "#{index}/2"])
      described_class.new(options).send(:select, rows).map(&:id)
    end
    expect(selected).to eq([["smoke/first", "smoke/third"], ["smoke/second"]])
  end
end
