# frozen_string_literal: true

module Resolvers
  class InvoicesResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query invoices'

    argument :ids, [ID], required: false, description: 'List of invoice IDs to fetch'
    argument :page, Integer, required: false
    argument :limit, Integer, required: false
    argument :status, Types::Invoices::StatusTypeEnum, required: false
    argument :payment_status, [Types::Invoices::PaymentStatusTypeEnum], required: false

    type Types::Invoices::Object.collection_type, null: false

    def resolve(ids: nil, page: nil, limit: nil, payment_status: nil, status: nil)
      validate_organization!

      invoices = current_organization
        .invoices
        .order(issuing_date: :desc)
        .page(page)
        .per(limit)

      invoices = invoices.where(status:) if status.present?
      invoices = invoices.where(payment_status:) if payment_status.present?
      invoices = invoices.where(id: ids) if ids.present?

      invoices
    end
  end
end
