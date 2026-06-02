# frozen_string_literal: true

module Types
  module QuoteVersions
    class ManualVoidReasonEnum < Types::BaseEnum
      graphql_name "QuoteVersionManualVoidReasonEnum"

      QuoteVersion::MANUAL_VOID_REASONS.keys.each do |reason|
        value reason
      end
    end
  end
end
