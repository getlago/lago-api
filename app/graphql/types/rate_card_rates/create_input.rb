# frozen_string_literal: true

module Types
  module RateCardRates
    # Same shape as the nested rates of a rate card creation, plus the card
    # to append to.
    class CreateInput < Input
      graphql_name "CreateRateCardRateInput"
      description "Create rate card rate input arguments"

      argument :rate_card_id, ID, required: true
    end
  end
end
