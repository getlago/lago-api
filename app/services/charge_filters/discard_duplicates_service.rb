# frozen_string_literal: true

module ChargeFilters
  class DiscardDuplicatesService < BaseService
    Result = BaseResult[:duplicate_groups, :discarded_filter_ids]

    KEEPER_STRATEGIES = %w[intact_then_oldest oldest newest].freeze

    BATCH_SIZE = 500

    DuplicateGroup = Struct.new(
      :metric_code, :plan_id, :charge_id, :predicate, :filters, :keeper, :skip_reason,
      keyword_init: true
    ) do
      def skipped? = skip_reason.present?

      def filters_to_discard = skipped? ? [] : filters - [keeper]
    end

    def initialize(organization:, plan: nil, dry_run: true, keeper_strategy: "intact_then_oldest")
      @organization = organization
      @plan = plan
      @dry_run = dry_run
      @keeper_strategy = keeper_strategy.to_s

      super
    end

    def call
      unless KEEPER_STRATEGIES.include?(keeper_strategy)
        return result.validation_failure!(
          errors: {keeper_strategy: ["must be one of #{KEEPER_STRATEGIES.join(", ")}"]}
        )
      end

      result.duplicate_groups = duplicate_groups
      result.discarded_filter_ids = []

      return result if dry_run

      filters_to_discard = duplicate_groups.flat_map(&:filters_to_discard)
      return result if filters_to_discard.empty?

      discard_filters(filters_to_discard)
      result.discarded_filter_ids = filters_to_discard.map(&:id)

      expire_usage_caches
      refresh_draft_invoices

      result
    end

    private

    attr_reader :organization, :plan, :dry_run, :keeper_strategy

    def duplicate_groups
      @duplicate_groups ||= duplicate_group_rows.each_slice(BATCH_SIZE).flat_map { build_groups(it) }
    end

    def duplicate_group_rows
      @duplicate_group_rows ||= ActiveRecord::Base.connection.select_all(duplicate_groups_sql).to_a
    end

    def duplicate_groups_sql
      <<~SQL
        WITH filters AS (
            SELECT
                bm.code AS code,
                c.plan_id AS plan_id,
                c.id AS charge_id,
                cf.id AS charge_filter_id,
                jsonb_object_agg(
                    bmf.key,
                    CASE
                        WHEN '#{ChargeFilterValue::ALL_FILTER_VALUES}' = ANY (cfv.values)
                        THEN bmf.values
                        ELSE cfv.values
                    END
                ) AS charge_filters
            FROM billable_metrics bm
            INNER JOIN charges c
                ON c.billable_metric_id = bm.id
               AND c.deleted_at IS NULL
            INNER JOIN charge_filters cf
                ON cf.charge_id = c.id
               AND cf.deleted_at IS NULL
            INNER JOIN charge_filter_values cfv
                ON cfv.charge_filter_id = cf.id
               AND cfv.deleted_at IS NULL
            INNER JOIN billable_metric_filters bmf
                ON bmf.id = cfv.billable_metric_filter_id
               AND bmf.deleted_at IS NULL
            WHERE bm.deleted_at IS NULL
              #{organization_condition}
              #{plan_condition}
            GROUP BY bm.code, c.plan_id, c.id, cf.id
        )

        SELECT
            code,
            plan_id,
            charge_id,
            array_agg(charge_filter_id) AS charge_filter_ids,
            charge_filters
        FROM filters
        GROUP BY code, plan_id, charge_id, charge_filters
        HAVING count(*) > 1
      SQL
    end

    def organization_condition
      ActiveRecord::Base.sanitize_sql_array(["AND bm.organization_id = ?", organization.id])
    end

    def plan_condition
      return "" if plan.nil?

      ActiveRecord::Base.sanitize_sql_array(["AND c.plan_id = ?", plan.id])
    end

    def build_groups(rows)
      filter_ids = rows.flat_map { parse_uuid_array(it["charge_filter_ids"]) }
      filters_by_id = ChargeFilter.where(id: filter_ids).includes(values: :billable_metric_filter).index_by(&:id)
      broadened_ids = broadened_filter_ids(filter_ids)

      rows.map do |row|
        filters = parse_uuid_array(row["charge_filter_ids"]).filter_map { filters_by_id[it] }

        group = DuplicateGroup.new(
          metric_code: row["code"],
          plan_id: row["plan_id"],
          charge_id: row["charge_id"],
          predicate: row["charge_filters"],
          filters:
        )

        if filters.size < 2 || model_predicates(filters).uniq.size != 1
          # The query and ChargeFilter#to_h_with_all_values disagree, so we cannot prove these
          # filters are duplicates. Never discard on a disagreement.
          group.skip_reason = "model predicate disagrees with the query"
        else
          group.keeper = select_keeper(filters, broadened_ids)
          group.skip_reason = "every filter lost a condition, keeper is ambiguous" if group.keeper.nil?
        end

        group
      end
    end

    # Re-derives each filter's predicate through the model the billing code itself uses, so the
    # SQL grouping is confirmed before anything is discarded.
    def model_predicates(filters)
      filters.map { it.to_h_with_all_values.transform_values(&:sort) }
    end

    # Filters that lost at least one condition to a billable metric filter edit.
    def broadened_filter_ids(filter_ids)
      ChargeFilterValue
        .with_discarded
        .where(charge_filter_id: filter_ids)
        .where.not(deleted_at: nil)
        .unscope(:order)
        .distinct
        .pluck(:charge_filter_id)
        .to_set
    end

    def select_keeper(filters, broadened_ids)
      oldest_first = filters.sort_by { [it.created_at, it.id] }

      case keeper_strategy
      when "oldest" then oldest_first.first
      when "newest" then oldest_first.last
      when "intact_then_oldest"
        intact = filters.reject { broadened_ids.include?(it.id) }

        # No filter kept all its conditions: every candidate is a broadened filter, so the DB
        # cannot tell us which price was intended. Leave the group alone.
        return nil if intact.empty?

        # A trim rewrites a condition row in place and leaves no trace, so a group can collapse
        # with every filter looking intact. Fall back to the oldest, the same tie-break
        # ChargeFilters::MatchingAndIgnoredService already applies to identical filters.
        intact.min_by { [it.created_at, it.id] }
      end
    end

    def discard_filters(filters)
      # Discarding a filter touches its charge, which touches its plan. Suppress the plan touch
      # so a handful of hot plan rows are not updated once per discarded filter. The charge touch
      # is kept: the usage cache key depends on charge.updated_at.
      Plan.no_touching do
        filters.each_slice(BATCH_SIZE) do |batch|
          ActiveRecord::Base.transaction do
            batch.each do |filter|
              freeze_invoice_display_name(filter)

              ChargeFilters::DestroyService.call!(charge_filter: filter, cascade_updates: false)
            end
          end
        end
      end
    end

    # ChargeFilter#display_name reads the kept condition rows, so a discarded filter renders
    # blank on any invoice PDF regenerated later. Freeze the label while it can still be built.
    def freeze_invoice_display_name(filter)
      return if filter.invoice_display_name.present?

      label = filter.to_h_with_discarded.values.flatten.uniq.join(", ")
      return if label.blank?

      filter.update_column(:invoice_display_name, label) # rubocop:disable Rails/SkipsModelValidations
    end

    def expire_usage_caches
      Subscription
        .where(plan_id: affected_plan_ids, status: %w[active pending])
        .in_batches(of: BATCH_SIZE) { Subscriptions::ChargeCacheService.expire_for_subscriptions(it.pluck(:id)) }
    end

    def refresh_draft_invoices
      BillableMetric.where(organization:, code: affected_metric_codes).ids.each do |billable_metric_id|
        BillableMetricFilters::RefreshDraftInvoicesJob.perform_later(billable_metric_id)
      end
    end

    def affected_plan_ids
      @affected_plan_ids ||= repaired_groups.map(&:plan_id).uniq
    end

    def affected_metric_codes
      @affected_metric_codes ||= repaired_groups.map(&:metric_code).uniq
    end

    def repaired_groups
      @repaired_groups ||= duplicate_groups.reject(&:skipped?)
    end

    # select_all decodes a uuid[] column into an Array with the postgres adapter, but returns the
    # raw "{a,b}" string on some type map configurations.
    def parse_uuid_array(value)
      return value if value.is_a?(Array)

      value.to_s.delete("{}").split(",")
    end
  end
end
