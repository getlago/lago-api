# frozen_string_literal: true

module ChargeFilters
  class CreateOrUpdateBatchService < BaseService
    def initialize(charge:, filters_params:)
      @charge = charge
      @filters_params = filters_params

      super
    end

    def call
      result.filters = []

      if filters_params.empty?
        remove_all

        return result
      end

      # We only care about order when you have less than 100 filters.
      touch = filters_params.size < 100

      ActiveRecord::Base.transaction do
        filters_params.each do |filter_param|
          # NOTE: since a filter could be a refinement of another one, we have to make sure
          #       that we are targeting the right one
          filter = filters.find do |f|
            f.to_h.sort == filter_param[:values].sort
          end

          filter ||= charge.filters.new

          filter.invoice_display_name = filter_param[:invoice_display_name]
          filter.properties = filter_param[:properties]
          if filter.save! && touch && !filter.changed?
            # NOTE: Make sure update_at is touched even if not changed to keep the right order
            filter.touch # rubocop:disable Rails/SkipsModelValidations
          end

          # NOTE: Create or update the filter values
          filter_param[:values].each do |key, values|
            billable_metric_filter = charge.billable_metric.filters.find_by(key:)

            filter_value = filter.values.find_or_initialize_by(
              billable_metric_filter_id: billable_metric_filter&.id
            )

            filter_value.values = values
            if filter_value.save! && touch && !filter_value.changed?
              # NOTE: Make sure update_at is touched even if not changed to keep the right order
              filter_value.touch # rubocop:disable Rails/SkipsModelValidations
            end
          end

          result.filters << filter
        end

        # NOTE: remove old filters that were not created or updated
        charge.filters.where.not(id: result.filters.map(&:id)).find_each do
          remove_filter(_1)
        end
      end

      result
    end

    private

    attr_reader :charge, :filters_params

    def filters
      @filters ||= charge.filters.includes(values: :billable_metric_filter)
    end

    def remove_all
      ActiveRecord::Base.transaction do
        charge.filters.each { remove_filter(_1) }
      end
    end

    def remove_filter(filter)
      filter.values.each(&:discard!)
      filter.discard!
    end
  end
end
