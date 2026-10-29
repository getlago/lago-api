# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::Stores::BaseStore do
  describe "BLANK_VALUE_CHARS" do
    it "lists the characters Ruby's blank? reads as blank" do
      blank_chars = (0..0xFFFF).filter_map do |codepoint|
        next if (0xD800..0xDFFF).cover?(codepoint)

        char = codepoint.chr(Encoding::UTF_8)
        char if char.blank?
      end

      expect(described_class::BLANK_VALUE_CHARS).to match_array(blank_chars)
    end
  end
end
