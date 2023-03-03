# frozen_string_literal: true

module Fees
  class CreateInstantService < BaseService
    def initialize(charge:, event:)
      @charge = charge
      @event = event

      super
    end

    def call
      result
    end

    private

    attr_reader :charge, :event
  end
end
