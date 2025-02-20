# frozen_string_literal: true

require "rails_helper"

RSpec.describe MoneyHelper do
  subject(:helper) { described_class }

  describe ".format" do
    let(:currency) { "USD" }
    let(:amount) { Money.new(100, currency) }

    it "formats the amount" do
      expect(helper.format(amount)).to eq("$1.00")
    end

    context "when currency does not use a well known symbol" do
      let(:currency) { "BHD" }

      it "formats the amount" do
        expect(helper.format(amount)).to eq("BHD 0.100")
      end
    end
  end

  describe ".format_with_precision" do
    let(:currency) { "USD" }

    it "rounds big decimals to 6 digits" do
      html = helper.format_with_precision(BigDecimal("123.12345678"), currency)

      expect(html).to eq("$123.123457")
    end

    it "shows six significant digits for values < 1" do
      html = helper.format_with_precision(BigDecimal("0.000000012345"), currency)

      expect(html).to eq("$0.000000012345")
    end

    it "shows only six significant digits for values < 1" do
      html = helper.format_with_precision(BigDecimal("0.100000012345"), currency)

      expect(html).to eq("$0.10")
    end

    context "when currency does not use a well known symbol" do
      let(:currency) { "BHD" }

      it "rounds big decimals to 6 digits" do
        html = helper.format_with_precision(BigDecimal("123.12345678"), currency)

        expect(html).to eq("BHD 123.123457")
      end

      it "shows six significant digits for values < 1" do
        html = helper.format_with_precision(BigDecimal("0.000000012345"), currency)

        expect(html).to eq("BHD 0.000000012345")
      end

      it "shows only six significant digits for values < 1" do
        html = helper.format_with_precision(BigDecimal("0.100000012345"), currency)

        expect(html).to eq("BHD 0.100")
      end
    end
  end
end
