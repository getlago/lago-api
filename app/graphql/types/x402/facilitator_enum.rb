# frozen_string_literal: true

module Types
  module X402
    class FacilitatorEnum < Types::BaseEnum
      graphql_name "X402FacilitatorEnum"

      ::X402::Connection::FACILITATORS.keys.each do |facilitator|
        value facilitator
      end
    end
  end
end
