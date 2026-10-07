# frozen_string_literal: true

module Types
  module AttributedUsage
    class BasisEnum < Types::BaseEnum
      graphql_name "AttributedUsageBasisEnum"

      UsageAttributions::QueryService::BASES.each do |basis|
        value basis
      end
    end
  end
end
