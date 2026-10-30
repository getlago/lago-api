# frozen_string_literal: true

module Types
  module X402
    class UpdateConnectionInput < Types::BaseInputObject
      graphql_name "UpdateX402ConnectionInput"

      argument :id, ID, required: true

      argument :code, String, required: false
      argument :name, String, required: false

      argument :allowed_origins, [String], required: false
      argument :auto_create_customers, Boolean, required: false
      argument :cdp_api_key_id, String, required: false
      argument :cdp_api_key_secret, String, required: false
      argument :networks, [String], required: false
      argument :payout_addresses, Types::X402::PayoutAddressesInput, required: false
    end
  end
end
