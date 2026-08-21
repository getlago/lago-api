# frozen_string_literal: true

module QuoteVersions
  module Validators
    # The billing entity a deal is issued by is a reference on the version, like the quoted plans and
    # add-ons, so it is checked here rather than resolved by the writing services. A blank value is
    # legitimate: the deal then follows the customer's own entity.
    #
    # Expects the includer to expose `quote_version`.
    module BillingEntityValidation
      extend ActiveSupport::Concern

      private

      # organization.billing_entities is scoped to the active, non-deleted ones, so an archived
      # entity cannot be quoted either.
      def validate_billing_entity
        return if quote_version.billing_entity_id.blank?
        return if quote_version.organization.billing_entities.exists?(id: quote_version.billing_entity_id)

        add_error(field: :billing_entity_id, error_code: "billing_entity_not_found")
      end
    end
  end
end
