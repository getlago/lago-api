# frozen_string_literal: true

module Types
  module Integrations
    class Quickbooks
      class VerifyConnectionInput < Types::BaseInputObject
        graphql_name "VerifyQuickbooksIntegrationConnectionInput"

        argument :id, ID, required: true
      end
    end
  end
end
