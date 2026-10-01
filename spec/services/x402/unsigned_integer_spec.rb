# frozen_string_literal: true

require "rails_helper"

describe X402::UnsignedInteger do
  describe ".parse" do
    subject(:parsed) { described_class.parse(value) }

    {1000 => 1000, 0 => 0, "1000" => 1000, "0" => 0, "010" => 10}.each do |input, expected|
      context "with #{input.inspect}" do
        let(:value) { input }

        it { is_expected.to eq(expected) }
      end
    end

    [-1, 1.9, "0x10", "1_000", " 7 ", "1.5", "-1", "", nil, []].each do |input|
      context "with #{input.inspect}" do
        let(:value) { input }

        it { is_expected.to be_nil }
      end
    end
  end
end
