# frozen_string_literal: true

module BillingEntities
  module Taxes
    class BaseService < BaseService
      private

      attr_reader :billing_entity

      def refresh_draft_invoices
        draft_invoice_ids = billing_entity.invoices.draft.pluck(:id)

        Invoice.where(id: draft_invoice_ids).update_all(ready_to_be_refreshed: true) # rubocop:disable Rails/SkipsModelValidations
      end
    end
  end
end
