# frozen_string_literal: true

module AddOns
  class UpdateService < BaseService
    def self.call(...)
      new(...).call
    end

    def initialize(add_on:, params:)
      @add_on = add_on
      @params = params
      super
    end

    def call
      return result.not_found_failure!(resource: 'add_on') unless add_on

      add_on.name = params[:name]
      add_on.code = params[:code]
      add_on.description = params[:description]
      add_on.amount_cents = params[:amount_cents]
      add_on.amount_currency = params[:amount_currency]

      add_on.save!

      result.add_on = add_on
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :add_on, :params
  end
end
