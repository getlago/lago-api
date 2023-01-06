# frozen_string_literal: true

module Queries
  class BaseQuery < BaseService
    def initialize(organization:)
      @organization = organization

      super
    end

    private

    attr_reader :organization
  end
end
