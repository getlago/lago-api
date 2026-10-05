# frozen_string_literal: true

require "rails_helper"

describe X402::Keccak256 do
  describe ".hexdigest" do
    subject(:hexdigest) { described_class.hexdigest(message) }

    {
      "" => "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470",
      "abc" => "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45",
      "a" * 135 => "34367dc248bbd832f4e3e69dfaac2f92638bd0bbd18f2912ba4ef454919cf446",
      "a" * 136 => "a6c4d403279fe3e0af03729caada8374b5ca54d8065329a3ebcaeb4b60aa386e",
      "a" * 137 => "d869f639c7046b4929fc92a4d988a8b22c55fbadb802c0c66ebcd484f1915f39",
      "a" * 271 => "132f47effd6c8b1b299efa53fe68aece77ec8ae4eb2e294f668eec94f76001e1",
      "b" * 272 => "5033eb030ec6c7bed2a3969d11847ddf89ec685b1e0b4ec9601ddba40a3b2ebf"
    }.each do |input, expected|
      context "with a #{input.bytesize}-byte message" do
        let(:message) { input }

        it { is_expected.to eq(expected) }
      end
    end

    context "with the empty message" do
      let(:message) { "" }

      it "differs from SHA3-256, which pads differently" do
        expect(hexdigest).not_to eq("a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a")
      end
    end
  end

  describe ".digest" do
    it "returns 32 binary bytes" do
      expect(described_class.digest("abc").bytesize).to eq(32)
    end
  end
end
