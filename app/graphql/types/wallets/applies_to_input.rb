# frozen_string_literal: true

module Types
  module Wallets
    class AppliesToInput < BaseInputObject
      argument :fee_types, [Types::Fees::TypesEnum], required: false
    end
  end
end
