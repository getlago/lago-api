# frozen_string_literal: true

module Types
  module IntegrationCustomers
    class SetAsDefaultInput < BaseInputObject
      description "Set an integration connection as the default for its category input arguments"

      argument :category, Types::IntegrationCustomers::ConnectionCategoryEnum, required: true
      argument :code, String, required: true
      argument :customer_id, ID, required: true
    end
  end
end
