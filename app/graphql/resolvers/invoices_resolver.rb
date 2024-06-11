# frozen_string_literal: true

module Resolvers
  class InvoicesResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = 'invoices:view'

    description 'Query invoices'

    argument :ids, [ID], required: false, description: 'List of invoice IDs to fetch'
    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :payment_dispute_lost, Boolean, required: false
    argument :payment_overdue, Boolean, required: false
    argument :payment_status, [Types::Invoices::PaymentStatusTypeEnum], required: false
    argument :search_term, String, required: false
    argument :status, Types::Invoices::StatusTypeEnum, required: false

    type Types::Invoices::Object.collection_type, null: false

    def resolve( # rubocop:disable Metrics/ParameterLists
      ids: nil,
      page: nil,
      limit: nil,
      payment_status: nil,
      status: nil,
      search_term: nil,
      payment_dispute_lost: nil,
      payment_overdue: nil
    )
      query = InvoicesQuery.new(organization: current_organization)
      result = query.call(
        search_term:,
        page:,
        limit:,
        payment_status:,
        payment_dispute_lost:,
        payment_overdue:,
        status:,
        filters: {
          ids:
        }
      )

      result.invoices
    end
  end
end
