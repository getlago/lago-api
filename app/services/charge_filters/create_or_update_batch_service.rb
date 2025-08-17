# frozen_string_literal: true

module ChargeFilters
  class CreateOrUpdateBatchService < BaseService
    def initialize(charge:, filters_params:, cascade_options: {})
      @charge = charge
      @filters_params = filters_params
      @cascade_updates = cascade_options[:cascade]
      @parent_filters_attributes = cascade_options[:parent_filters] || []
      @parent_filters = if parent_filters_attributes.blank?
        ChargeFilter.none
      else
        ChargeFilter.with_discarded.where(id: parent_filters_attributes.map { |f| f["id"] })
      end

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

          # Skip cascade update if properties are already touched
          if cascade_updates && filter && parent_filters
            parent_filter = parent_filters.find do |pf|
              pf.to_h.sort == filter.to_h.sort
            end

            if parent_filter.blank? || parent_filter_properties(parent_filter) != filter.properties
              # Make sure that pricing group keys are cascaded even if properties are overridden
              cascade_pricing_group_keys(filter, filter_param)
              filter.save!

              PaperTrail.request.disable_model(filter.class)
              # NOTE: Make sure update_at is touched even if not changed to keep the order
              filter.touch # rubocop:disable Rails/SkipsModelValidations
              PaperTrail.request.enable_model(filter.class)
              result.filters << filter

              next
            end
          end

          filter ||= charge.filters.new(organization_id: charge.organization_id)

          filter.invoice_display_name = filter_param[:invoice_display_name]
          filter.properties = ChargeModels::FilterPropertiesService.call(
            chargeable: charge,
            properties: filter_param[:properties]
          ).properties
          if filter.save! && touch && !filter.changed?
            PaperTrail.request.disable_model(filter.class)
            # NOTE: Make sure update_at is touched even if not changed to keep the right order
            filter.touch # rubocop:disable Rails/SkipsModelValidations
            PaperTrail.request.enable_model(filter.class)
          end

          # NOTE: Create or update the filter values
          filter_param[:values].each do |key, values|
            billable_metric_filter = charge.billable_metric.filters.find_by(key:)

            filter_value = filter.values.find_or_initialize_by(
              billable_metric_filter_id: billable_metric_filter&.id
            ) { it.organization_id = charge.organization_id }

            filter_value.values = values
            if filter_value.save! && touch && !filter_value.changed?
              PaperTrail.request.disable_model(filter_value.class)
              # NOTE: Make sure update_at is touched even if not changed to keep the right order
              filter_value.touch # rubocop:disable Rails/SkipsModelValidations
              PaperTrail.request.enable_model(filter_value.class)
            end
          end

          result.filters << filter
        end

        # NOTE: remove old filters that were not created or updated
        remove_query = charge.filters
        remove_query = remove_query.where(id: inherited_filter_ids) if cascade_updates && parent_filters
        remove_query.where.not(id: result.filters.map(&:id)).unscope(:order).find_each do
          remove_filter(it)
        end
      end

      result
    end

    private

    attr_reader :charge, :filters_params, :cascade_updates, :parent_filters, :parent_filters_attributes

    def filters
      @filters ||= charge.filters.includes(values: :billable_metric_filter)
    end

    def parent_filter_properties(parent_filter)
      match = parent_filters_attributes.find do |f|
        f["id"] == parent_filter.id
      end

      match["properties"]
    end

    def remove_all
      ActiveRecord::Base.transaction do
        if cascade_updates
          charge.filters.where(id: inherited_filter_ids).unscope(:order).find_each { remove_filter(it) }
        else
          charge.filters.each { remove_filter(it) }
        end
      end
    end

    def remove_filter(filter)
      filter.values.each(&:discard!)
      filter.discard!
    end

    def inherited_filter_ids
      return @inherited_filter_ids if defined? @inherited_filter_ids

      @inherited_filter_ids = []

      return @inherited_filter_ids if parent_filters.blank? || !cascade_updates

      parent_filters.unscope(:order).find_each do |pf|
        value = pf.to_h_with_discarded.sort

        match = filters.find do |f|
          value == f.to_h.sort
        end

        @inherited_filter_ids << match.id if match
      end

      @inherited_filter_ids
    end

    def cascade_pricing_group_keys(filter, params)
      pricing_group_keys = params.dig(:properties, :pricing_group_keys) || params.dig(:properties, :grouped_by)

      if pricing_group_keys
        filter.properties["pricing_group_keys"] = pricing_group_keys
        filter.properties.delete("grouped_by")
      elsif filter.pricing_group_keys.present?
        filter.properties.delete("pricing_group_keys")
        filter.properties.delete("grouped_by")
      end
    end
  end
end
