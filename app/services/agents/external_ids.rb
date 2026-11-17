# frozen_string_literal: true

module Agents
  module ExternalIds
    def self.customer(registration)
      "agent_#{registration.id}"
    end

    def self.subscription(registration)
      customer(registration)
    end

    # The same ids as a subquery, for a lookup over all the registrations of a storefront.
    def self.of(registrations)
      registrations.select(Arel.sql("'agent_' || id::text"))
    end
  end
end
