# frozen_string_literal: true

module AddOns
  class DestroyService < BaseService
    Result = BaseResult[:add_on]

    def initialize(add_on:)
      @add_on = add_on
      super
    end

    def call
      return result.not_found_failure!(resource: "add_on") unless add_on

      add_on.discard!

      result.add_on = add_on
      result
    end

    private

    attr_reader :add_on
  end
end
