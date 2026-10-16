# frozen_string_literal: true

module V2
  module Invoices
    class ContractSerializer < ModelSerializer
      def serialize
        {
          lago_id: model.id,
          external_id: model.external_id
        }
      end
    end
  end
end
