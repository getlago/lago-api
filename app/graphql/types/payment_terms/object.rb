# frozen_string_literal: true

module Types
  module PaymentTerms
    class Object < Types::BaseObject
      graphql_name "PaymentTerm"
      description "Structured payment term"

      field :day_of_month, Integer, null: true
      field :days, Integer, null: true
      field :month_offset, Integer, null: true
      field :term_type, Types::PaymentTerms::TermTypeEnum, null: false
    end
  end
end
