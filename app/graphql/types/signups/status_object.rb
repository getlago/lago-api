# frozen_string_literal: true

module Types
  module Signups
    class StatusObject < Types::BaseObject
      graphql_name "SignupStatus"
      description "The state of a self-serve signup, for the tab that started it"

      field :resend_available_in_seconds, Integer, null: true, description: "Null when this signup cannot send more emails"
      field :resend_limit_reached, Boolean, null: false
      field :status, Types::Signups::StatusEnum, null: false
    end
  end
end
