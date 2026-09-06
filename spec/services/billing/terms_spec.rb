# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Terms do
  describe "TIMINGS" do
    it "is the two supported billing timings" do
      expect(described_class::TIMINGS).to eq(%i[advance arrears])
    end
  end

  describe ".new" do
    it "accepts advance" do
      expect(described_class.new(timing: :advance, prorated: true).timing).to eq(:advance)
    end

    it "accepts arrears" do
      expect(described_class.new(timing: :arrears, prorated: false).timing).to eq(:arrears)
    end

    it "symbolizes a string timing" do
      expect(described_class.new(timing: "advance", prorated: true)).to eq(described_class.new(timing: :advance, prorated: true))
    end

    it "keeps prorated" do
      expect(described_class.new(timing: :advance, prorated: false).prorated).to be(false)
    end

    it "raises on an unknown timing" do
      expect { described_class.new(timing: :monthly, prorated: true) }.to raise_error(ArgumentError, /unknown billing timing/)
    end

    it "raises on a nil timing" do
      expect { described_class.new(timing: nil, prorated: true) }.to raise_error(ArgumentError, /unknown billing timing/)
    end

    it "raises on a non-boolean prorated" do
      expect { described_class.new(timing: :advance, prorated: nil) }.to raise_error(ArgumentError, /must be true or false/)
    end

    it "raises on a truthy but non-boolean prorated" do
      expect { described_class.new(timing: :advance, prorated: "yes") }.to raise_error(ArgumentError, /must be true or false/)
    end

    it "is frozen" do
      expect(described_class.new(timing: :advance, prorated: true)).to be_frozen
    end
  end
end
