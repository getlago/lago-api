# frozen_string_literal: true

module Organizations
  class CreateService < BaseService
    def initialize(params)
      @params = params
      super
    end

    def call
      organization = Organization.new(params)

      ActiveRecord::Base.transaction do
        organization.save!
        organization.api_keys.create!
      end

      result.organization = organization
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :params
  end
end
