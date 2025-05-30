# frozen_string_literal: true

module Charges
  class DestroyChildrenService < BaseService
    Result = BaseResult[:charge]

    def initialize(charge)
      @charge = charge
      super
    end

    def call
      return result unless charge
      return result unless charge.discarded?

      ActiveRecord::Base.transaction do
        charge.children.find_each { Charges::DestroyService.call!(charge: it) }
      end

      result.charge = charge
      result
    end

    private

    attr_reader :charge
  end
end
