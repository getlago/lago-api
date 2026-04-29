# frozen_string_literal: true

module Types
  module QuoteVersions
    class VoidReasonEnum < Types::BaseEnum
      QuoteVersion::VOID_REASONS.keys.each do |reason|
        value reason
      end
    end
  end
end
