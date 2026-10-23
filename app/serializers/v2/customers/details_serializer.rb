# frozen_string_literal: true

module V2
  module Customers
    # Customer endpoints include the shipping address; embedded customers stay flat.
    class DetailsSerializer < V2::CustomerSerializer
      private

      def shipping_address_payload
        {shipping_address: model.shipping_address}
      end
    end
  end
end
