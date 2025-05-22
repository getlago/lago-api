# frozen_string_literal: true

module UsageMonitoring
  class Alert < ApplicationRecord
    include Discard::Model

    self.discard_column = :deleted_at
    self.inheritance_column = :alert_type

    STI_MAPPING = {
      "usage_amount" => "UsageMonitoring::UsageAmountAlert",
      "billable_metric_usage_amount" => "UsageMonitoring::BillableMetricUsageAmountAlert",
      "billable_metric_usage_units" => "UsageMonitoring::BillableMetricUsageUnitsAlert",

      "lifetime_usage_amount" => "UsageMonitoring::LifetimeUsageAmountAlert"
    }

    CURRENT_USAGE_TYPES = %w[usage_amount billable_metric_usage_amount billable_metric_usage_units]
    BILLABLE_METRIC_TYPES = %w[billable_metric_usage_amount billable_metric_usage_units]

    default_scope -> { kept }

    belongs_to :organization
    belongs_to :billable_metric, optional: true

    has_many :thresholds,
      foreign_key: :usage_monitoring_alert_id,
      class_name: "UsageMonitoring::AlertThreshold",
      dependent: :delete_all

    has_many :triggered_alerts,
      foreign_key: :usage_monitoring_alert_id,
      class_name: "UsageMonitoring::TriggeredAlert"

    validates :alert_type, presence: true, inclusion: {in: STI_MAPPING.keys}
    validates :code, presence: true
    validates :billable_metric, presence: true, if: :need_billable_metric?
    validates :billable_metric, absence: true, unless: :need_billable_metric?

    scope :using_current_usage, -> { where(alert_type: CURRENT_USAGE_TYPES) }
    scope :using_lifetime_usage, -> { where(alert_type: "lifetime_usage_amount") }

    def self.find_sti_class(type_name)
      STI_MAPPING.fetch(type_name).constantize
    end

    def self.sti_name
      STI_MAPPING.invert.fetch(name)
    end

    def find_thresholds_crossed(current)
      crossed = []
      return crossed if current < previous_value
      return crossed if current < one_time_thresholds_values.first

      if previous_value < one_time_thresholds_values.last
        crossed += one_time_thresholds_values.filter { |t| t.between?(previous_value, current) }
      end

      crossed += find_recurring_thresholds_crossed(
        previous_value, current, recurring_threshold&.value, one_time_thresholds_values.last
      )

      crossed.uniq.sort
    end

    def recurring_threshold
      @recurring_threshold ||= thresholds.find { |th| th.recurring }
    end

    def one_time_thresholds_values
      @one_time_thresholds_values ||= thresholds.all.filter_map { |th| th.value unless th.recurring }.uniq.sort
    end

    def formatted_crossed_thresholds(crossed_threshold_values)
      regular_thresholds_values, recurring_thresholds_values = crossed_threshold_values.partition do |v|
        one_time_thresholds_values.include?(v)
      end

      formatted_regular_thresholds = thresholds
        .filter { regular_thresholds_values.include?(it.value) }
        .map { |t| {code: t.code, value: t.value, recurring: false} }

      formatted_recurring_thresholds = recurring_thresholds_values
        .map { |v| {code: recurring_threshold&.code, value: v, recurring: true} }

      formatted_regular_thresholds + formatted_recurring_thresholds
    end

    def find_value(current_metrics)
      raise NotImplementedError
    end

    private

    def need_billable_metric?
      BILLABLE_METRIC_TYPES.include?(alert_type)
    end

    def find_recurring_thresholds_crossed(previous, current, step, initial)
      return [] unless step

      previous_steps = ((previous - initial) / step).ceil
      previous_recurring = initial + [previous_steps, 1].max * step

      current_steps = ((current - initial) / step).floor
      current_recurring = initial + current_steps * step

      return [] if previous_recurring > current_recurring # Shouldn't happen

      (previous_recurring..current_recurring).step(step).to_a
    end
  end
end

# == Schema Information
#
# Table name: usage_monitoring_alerts
#
#  id                       :uuid             not null, primary key
#  alert_type               :enum             not null
#  code                     :string           not null
#  deleted_at               :datetime
#  last_processed_at        :datetime
#  name                     :string
#  previous_value           :decimal(30, 5)   default(0.0), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  billable_metric_id       :uuid
#  organization_id          :uuid             not null
#  subscription_external_id :string           not null
#
# Indexes
#
#  idx_alerts_code_unique_per_subscription                    (code,subscription_external_id,organization_id) UNIQUE WHERE (deleted_at IS NULL)
#  idx_alerts_unique_per_type_per_subscription                (subscription_external_id,organization_id,alert_type) UNIQUE WHERE ((billable_metric_id IS NULL) AND (deleted_at IS NULL))
#  idx_alerts_unique_per_type_per_subscription_with_bm        (subscription_external_id,organization_id,alert_type,billable_metric_id) UNIQUE WHERE ((billable_metric_id IS NOT NULL) AND (deleted_at IS NULL))
#  index_usage_monitoring_alerts_on_billable_metric_id        (billable_metric_id)
#  index_usage_monitoring_alerts_on_organization_id           (organization_id)
#  index_usage_monitoring_alerts_on_subscription_external_id  (subscription_external_id)
#
# Foreign Keys
#
#  fk_rails_...  (billable_metric_id => billable_metrics.id)
#  fk_rails_...  (organization_id => organizations.id)
#
