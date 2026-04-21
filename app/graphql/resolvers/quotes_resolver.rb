# frozen_string_literal: true

module Resolvers
  class QuotesResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "quotes:view"

    description "Query quotes of an organization"

    argument :customer, [ID], required: false
    argument :from_date, GraphQL::Types::ISO8601Date, required: false
    argument :latest_version_only, Boolean, required: false
    argument :limit, Integer, required: false
    argument :number, [String], required: false
    argument :owners, [ID], required: false
    argument :page, Integer, required: false
    argument :status, [Types::Quotes::StatusEnum], required: false
    argument :to_date, GraphQL::Types::ISO8601Date, required: false
    argument :version, [Integer], required: false

    type Types::Quotes::Object.collection_type, null: false

    def resolve(page: nil, limit: nil, customer: nil, number: nil, latest_version_only: false, status: nil, version: nil, from_date: nil, to_date: nil, owners: nil)
      result = ::QuotesQuery.call(
        organization: current_organization,
        filters: {
          customer:,
          status:,
          number:,
          version:,
          from_date:,
          to_date:,
          owners:
        },
        latest_version_only:,
        pagination: {page:, limit:}
      )
      return result_error(result) unless result.success?

      result.quotes.includes(:customer, :organization, :subscription, :owners)
    end
  end
end
