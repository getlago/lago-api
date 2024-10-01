# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MoneyHelper do
  subject(:helper) { described_class }

  describe '.format_with_precision' do
    it 'rounds big decimals to 6 digits' do
      html = helper.format_with_precision(BigDecimal("123.12345678"), "USD")

      expect(html).to eq('$123.123457')
    end

    it 'shows six significant digits for values < 1' do
      html = helper.format_with_precision(BigDecimal("0.000000012345"), "USD")

      expect(html).to eq('$0.000000012345')
    end

    it 'shows only six significant digits for values < 1' do
      html = helper.format_with_precision(BigDecimal("0.100000012345"), "USD")

      expect(html).to eq('$0.10')
    end
  end
end
