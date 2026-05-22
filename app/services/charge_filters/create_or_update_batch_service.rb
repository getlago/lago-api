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

      return result.single_validation_failure!(field: :values, error_code: "value_is_mandatory") if empty_filter_values?

      # We only care about order when you have less than 100 filters.
      touch = filters_params.size < 100

      # NOTE: PaperTrail's per-save Version Create plus version_limit COUNT is the
      #       dominant DB cost for large filter batches (two queries per record save).
      #       Skip per-filter audit rows for this operation — the parent Plan/Charge
      #       still gets its own audit entry from their respective services.
      PaperTrail.request.disable_model(ChargeFilter)
      PaperTrail.request.disable_model(ChargeFilterValue)

      begin
        ActiveRecord::Base.transaction do
          # NOTE: the `with_discarded` scope on the belongs_to associations below defeats
          #       Rails' automatic inverse_of, so every save would otherwise re-SELECT the
          #       parent records during validation. Load each parent once and pre-assign
          #       it on every built/looked-up child.
          organization = charge.organization

          filters_params.each do |filter_param|
            # NOTE: callers pass either string-keyed (plan flow, via with_indifferent_access) or
            #       symbol-keyed (subscription override flow, via deep_symbolize_keys) values
            #       hashes. Normalize so the in-memory indexes below match regardless.
            values_params = filter_param[:values].transform_keys(&:to_s)

            # NOTE: since a filter could be a refinement of another one, we have to make sure
            #       that we are targeting the right one
            filter = filters_by_values_key[values_params.sort]
            matched_existing_filter = !filter.nil?

            filter ||= charge.filters.new(organization_id: charge.organization_id)
            filter.charge = charge
            filter.organization = organization

            filter.invoice_display_name = filter_param[:invoice_display_name]
            filter.properties = ChargeModels::FilterPropertiesService.call(
              chargeable: charge,
              properties: filter_param[:properties]&.deep_symbolize_keys&.except(:presentation_group_keys)
            ).properties

            filter.save! if filter.changed?

            # NOTE: Make sure updated_at is touched even if not changed to keep the right order.
            filter.touch if touch # rubocop:disable Rails/SkipsModelValidations

            # NOTE: Create or update the filter values
            values_params.each do |key, values|
              billable_metric_filter = billable_metric_filters_by_key[key]

              # NOTE: only look up an existing filter_value if the parent filter came from
              #       the preloaded set. For freshly-created filters, the values collection
              #       is provably empty — querying it on a now-persisted record issues a
              #       wasted SELECT per filter.
              filter_value = if matched_existing_filter
                filter.values.to_a.find { |v| v.billable_metric_filter_id == billable_metric_filter&.id }
              end
              filter_value ||= filter.values.build(organization_id: charge.organization_id)
              filter_value.charge_filter = filter
              filter_value.billable_metric_filter = billable_metric_filter
              filter_value.organization = organization

              filter_value.values = values
              filter_value.save! if filter_value.changed?

              # NOTE: Make sure updated_at is touched even if not changed to keep the right order.
              filter_value.touch if touch # rubocop:disable Rails/SkipsModelValidations
            end

            result.filters << filter
          end

          # NOTE: remove old filters that were not created or updated
          charge.filters.where.not(id: result.filters.map(&:id)).unscope(:order).find_each do
            remove_filter(it)
          end
        end
      ensure
        PaperTrail.request.enable_model(ChargeFilter)
        PaperTrail.request.enable_model(ChargeFilterValue)
      end

      result
    end

    private

    attr_reader :charge, :filters_params

    def filters
      @filters ||= charge.filters.includes(values: :billable_metric_filter)
    end

    def filters_by_values_key
      @filters_by_values_key ||= filters.index_by { |f| f.to_h.sort }
    end

    def billable_metric_filters_by_key
      @billable_metric_filters_by_key ||= charge.billable_metric.filters.index_by(&:key)
    end

    def remove_all
      ActiveRecord::Base.transaction do
        charge.filters.each { remove_filter(it) }
      end
    end

    def remove_filter(filter)
      filter.values.update_all(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      filter.discard!
    end

    def empty_filter_values?
      filters_params.any? { |filter_param| filter_param[:values].blank? }
    end
  end
end
