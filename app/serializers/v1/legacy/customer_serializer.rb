# frozen_string_literal: true

module V1
  module Legacy
    class CustomerSerializer < ModelSerializer
      def serialize
        {
          billing_configuration: {vat_rate: model.vat_rate},
        }
      end
    end
  end
end
