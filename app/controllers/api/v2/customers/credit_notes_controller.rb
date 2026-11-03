# frozen_string_literal: true

module Api
  module V2
    module Customers
      class CreditNotesController < Api::V2::BaseController
        include Api::V2::CreditNoteIndex

        serializable_with ::V2::CreditNoteSerializer, expand_on: []

        def index
          customer = current_organization.customers.find_by(external_id: params[:customer_external_id])
          return not_found_error(resource: "customer") unless customer

          credit_note_index(customer:)
        end

        private

        def resource_name
          "credit_note"
        end
      end
    end
  end
end
