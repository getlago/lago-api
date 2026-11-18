# frozen_string_literal: true

module Types
  module Signups
    class SourceEnum < Types::BaseEnum
      graphql_name "SignupSourceEnum"
      description "Where a user heard about Lago, asked at signup Step 3 and sent to analytics only"

      ::Signups::CreateOrganizationService::SOURCES.each { value it }
    end
  end
end
