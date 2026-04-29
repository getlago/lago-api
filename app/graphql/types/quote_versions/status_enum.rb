# frozen_string_literal: true

module Types
  module QuoteVersions
    class StatusEnum < Types::BaseEnum
      QuoteVersion::STATUSES.keys.each do |status|
        value status
      end
    end
  end
end
