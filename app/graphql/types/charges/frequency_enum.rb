# frozen_string_literal: true

module Types
  module Charges
    class FrequencyEnum < Types::BaseEnum
      graphql_name 'ChargeFrequency'

      Charge::FREQUENCIES.each do |type|
        value type
      end
    end
  end
end
