# frozen_string_literal: true

module Resolvers
  class InvoiceProductFeesResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "invoices:view"

    description "Query the product fees of an invoice, in the order of the invoice PDF"

    argument :invoice_id, ID, required: true

    argument :contract_id, ID, required: false
    argument :product_category_id, ID, required: false
    argument :product_filter_ids, [ID], required: false
    argument :product_ids, [ID], required: false
    argument :product_type, Types::Products::ProductTypeEnum, required: false
    argument :search_term, String, required: false
    argument :standalone_products, Boolean, required: false
    argument :without_product_filter, Boolean, required: false

    argument :limit, Integer, required: false
    argument :page, Integer, required: false

    type Types::Fees::Object.collection_type, null: false

    def resolve(invoice_id:, page: nil, limit: nil, search_term: nil, **filters)
      result = ::InvoiceProductFeesQuery.call(
        organization: current_organization,
        search_term:,
        pagination: {page:, limit:},
        filters: filters.merge(invoice_id:)
      )

      result.success? ? result.fees : result_error(result)
    end
  end
end
