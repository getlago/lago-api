# frozen_string_literal: true

require "rails_helper"

RSpec.describe DataExports::Csv::QuotedWriter do
  subject(:writer) { described_class.new(io) }

  let(:io) { StringIO.new }

  it "quotes every value and leaves nil as an empty unquoted field" do
    writer << ["name", "", nil, 42, 1.5, true]

    expect(io.string).to eq(%("name","",,"42","1.5","true"\n))
  end

  it "doubles embedded quotes and keeps separators inside the field" do
    writer << [%(a","b), "safe;=1+1;safe", "multi\nline"]

    expect(CSV.parse_line(io.string)).to eq([%(a","b), "safe;=1+1;safe", "multi\nline"])
    expect(io.string).to start_with(%("a"",""b",))
  end

  it "escapes formula values" do
    writer << ["=1+1", "-150"]

    expect(io.string).to eq(%("'=1+1","-150"\n))
  end

  it "writes one line per row" do
    writer << ["a"]
    writer << [nil, "b"]

    expect(CSV.parse(io.string)).to eq([["a"], [nil, "b"]])
  end
end
