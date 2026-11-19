# frozen_string_literal: true

module Agents
  module ExternalIds
    def self.customer(registration)
      "agent_#{registration.id}"
    end

    def self.subscription(registration)
      customer(registration)
    end
  end
end
