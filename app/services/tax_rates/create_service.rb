# frozen_string_literal: true

module TaxRates
  class CreateService < BaseService
    def initialize(organization:, params:)
      @organization = organization
      @params = params

      super
    end

    def call
      tax_rate = organization.tax_rates.create!(
        name: params[:name],
        code: params[:code],
        value: params[:value],
        description: params[:description],
      )

      result.tax_rate = tax_rate
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :organization, :params
  end
end
