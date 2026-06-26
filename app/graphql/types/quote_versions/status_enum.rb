# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module QuoteVersions
    class StatusEnum < Types::BaseEnum
      QuoteVersion::STATUSES.each_key do |status|
        value status
      end
    end
  end
end
