# frozen_string_literal: true

module QuoteVersions
  module Validators
    module SubscriptionCreation
      class StructuralValidator < BaseStructuralValidator
        private

        def schemer
          Schema.schemer(scope)
        end
      end
    end
  end
end
