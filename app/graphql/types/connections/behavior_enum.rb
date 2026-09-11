# frozen_string_literal: true

module Types
  module Connections
    class BehaviorEnum < Types::BaseEnum
      graphql_name "ConnectionBehaviorEnum"

      # "specific" is implied by supplying a code and is never sent. "inherit" is input-only: it
      # destroys the override row, since row absence is what ConnectionResolvable reads as
      # inheritance.
      BillingObjectConnections::ValidateService::BEHAVIORS.each do |behavior|
        value behavior
      end
    end
  end
end
