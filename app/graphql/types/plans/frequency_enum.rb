# frozen_string_literal: true

module Types
  module Plans
    class FrequencyEnum < Types::BaseEnum
      Plan::FREQUENCIES.each do |type|
        value type
      end
    end
  end
end
