# frozen_string_literal: true

module Queries
  class CreditNotesQueryFiltersContract < Dry::Validation::Contract
    params do
      optional(:amount_from).maybe(:integer)
      optional(:amount_to).maybe(:integer)
    end
  end
end
