# frozen_string_literal: true

module Analytics
  class BaseService < BaseService
    def initialize(organization, **filters)
      @organization = organization
      @filters = filters
      super()
    end

    private

    attr_reader :organization, :filters, :records
  end
end
