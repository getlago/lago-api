# frozen_string_literal: true

module V1
  module Invoices
    class ErrorDetailSerializer < ModelSerializer
      def serialize
        {
          lago_id: model.id,
          error_code: model.error_code,
          error_details: model.error_details
        }
      end
    end
  end
end
