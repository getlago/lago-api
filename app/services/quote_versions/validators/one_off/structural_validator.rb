# frozen_string_literal: true

module QuoteVersions
  module Validators
    module OneOff
      class StructuralValidator < BaseStructuralValidator
        private

        def schemer
          Schema.schemer(scope)
        end
      end
    end
  end
end
