# frozen_string_literal: true

module Types
  module X402
    class CreateConnectionInput < Types::BaseInputObject
      graphql_name "CreateX402ConnectionInput"

      argument :code, String, required: true
      argument :name, String, required: true

      argument :allowed_origins, [String], required: true
      argument :auto_create_customers, Boolean, required: false
      argument :cdp_api_key_id, String, required: true
      argument :cdp_api_key_secret, String, required: true
      argument :networks, [String], required: true
      argument :payout_addresses, Types::X402::PayoutAddressesInput, required: true
    end
  end
end
