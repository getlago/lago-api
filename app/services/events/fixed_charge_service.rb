# frozen_string_literal: true

module Events
  class FixedChargeService < BaseService
    def initialize(organization:, subscription:, boundaries:, code: nil, filters: {})
      @organization = organization
      @subscription = subscription
      @boundaries = boundaries
      @code = code
      @filters = filters.merge(source: 'fixed_charge')

      super
    end

    def call
      event_store_class = Events::Stores::StoreFactory.store_class(organization:)
      
      event_store = event_store_class.new(
        code:,
        subscription:,
        boundaries:,
        filters: @filters
      )

      result.event_store = event_store
      result
    end

    private

    attr_reader :organization, :subscription, :boundaries, :code, :filters
  end
end 