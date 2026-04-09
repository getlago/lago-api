# frozen_string_literal: true

module Types
  module Quotes
    class StatusEnum < Types::BaseEnum
      Quote::STATUSES.keys.each do |status|
        value status
      end
    end
  end
end
