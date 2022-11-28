# frozen_string_literal: true

module Resolvers
  module Customers
    class InvoicesResolver < Resolvers::BaseResolver
      include AuthenticableApiUser
      include RequiredOrganization

      description 'Query invoices of a customer'

      argument :customer_id, type: ID, required: true
      argument :status, Types::Invoices::StatusTypeEnum, required: false
      argument :page, Integer, required: false
      argument :limit, Integer, required: false

      type Types::Invoices::Object.collection_type, null: false

      def resolve(customer_id:, status: nil, page: nil, limit: nil)
        validate_organization!
        current_customer = Customer.find(customer_id)

        invoices = current_customer.invoices
        invoices = invoices.where(status: status) if status.present?
        invoices.order(created_at: :desc).page(page).per(limit)
      rescue ActiveRecord::RecordNotFound
        not_found_error(resource: 'customer')
      end
    end
  end
end
