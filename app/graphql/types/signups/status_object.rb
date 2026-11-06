# frozen_string_literal: true

module Types
  module Signups
    class StatusObject < Types::BaseObject
      graphql_name "SignupStatus"
      description "The state of a self-serve signup, for the tab that started it"

      field :status, Types::Signups::StatusEnum, null: false
    end
  end
end
