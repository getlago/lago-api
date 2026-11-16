# frozen_string_literal: true

module Types
  module Signups
    class StatusObject < Types::BaseObject
      graphql_name "SignupStatus"
      description "The state of a self-serve signup, for the tab that started it"

      field :resend_available_in_seconds, Integer, null: true, description: "Null when this signup cannot send more emails"
      field :resend_limit_reached, Boolean, null: false
      field :status, Types::Signups::StatusEnum, null: false

      # From the attempt's sends and the other emails to its mailbox, so a reloaded "Check your email" screen restores
      # its countdown. Computed only when asked for, so a poll for the status alone runs no mailbox query.
      def resend_available_in_seconds
        object[:pending_signup]&.resend_available_in_seconds(Time.current)
      end

      def resend_limit_reached
        object[:pending_signup]&.resend_limit_reached? || false
      end
    end
  end
end
