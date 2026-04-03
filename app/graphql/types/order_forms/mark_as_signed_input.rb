# frozen_string_literal: true

module Types
  module OrderForms
    class MarkAsSignedInput < Types::BaseInputObject
      description "Mark Order Form as signed input arguments"

      argument :id, ID, required: true
    end
  end
end
