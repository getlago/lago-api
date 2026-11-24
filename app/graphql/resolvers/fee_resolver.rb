# frozen_string_literal: true

module Resolvers
  class FeeResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "invoices:view"

    description "Query a single fee of an organization"

    argument :id, ID, required: true, description: "Uniq ID of the fee"

    type Types::Fees::Object, null: true

    def resolve(id:)
      context.scoped_set!(:preserve_add_on_fee_period_dates, true)
      current_organization.fees.joins(:invoice).merge(Invoice.visible).find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: "fee")
    end
  end
end
