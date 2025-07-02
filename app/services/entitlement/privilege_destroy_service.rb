# frozen_string_literal: true

module Entitlement
  class PrivilegeDestroyService < BaseService
    Result = BaseResult[:privilege]

    def initialize(privilege:)
      @privilege = privilege
      super
    end

    def call
      return result.not_found_failure!(resource: "privilege") unless privilege

      ActiveRecord::Base.transaction do
        privilege.discard!
      end

      result.privilege = privilege
      result
    end

    private

    attr_reader :privilege
  end
end
