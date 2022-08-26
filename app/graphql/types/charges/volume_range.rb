# frozen_string_literal: true

module Types
  module Charges
    class VolumeRange < Types::BaseObject
      graphql_name 'VolumeRange'

      field :from_value, Integer, null: false
      field :to_value, Integer, null: true

      field :per_unit_amount, String, null: false
      field :flat_amount, String, null: false
    end
  end
end
