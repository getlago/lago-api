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

    context "with the Slovak locale" do
      let(:currency) { "EUR" }
      let(:amount) { Money.new(123456, currency) }

      around { |example| I18n.with_locale(:sk) { example.run } }

      it "places the currency after the amount and uses Slovak separators" do
        expect(helper.format(amount)).to eq("1 234,56 €")
      end

      context "when currency does not use a well known symbol" do
        let(:currency) { "BHD" }

        it "places the ISO code after the amount" do
          expect(helper.format(amount)).to eq("123,456 BHD")
        end
      end
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

  describe ".format_pricing_unit" do
    subject { helper.format_pricing_unit(amount_cents, currency) }

    let(:currency) { build_stubbed(:pricing_unit) }
    let(:amount_cents) { 100 }

    it "formats the amount" do
      expect(subject).to eq "100.00 #{currency.short_name}"
    end
  end

  describe ".format_pricing_unit_with_precision" do
    subject { helper.format_pricing_unit_with_precision(amount, currency) }

    let(:currency) { build_stubbed(:pricing_unit) }

    context "when amount bigger than 1" do
      let(:amount) { BigDecimal("123.12345678") }

      it "rounds big decimals to 6 digits" do
        expect(subject).to eq "123.123457 #{currency.short_name}"
      end
    end

    context "when amount smaller than 1" do
      let(:amount) { BigDecimal("0.000000012345") }

      it "shows six significant digits for values < 1" do
        expect(subject).to eq "0.000000012345 #{currency.short_name}"
      end
    end
  end
end
