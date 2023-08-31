# frozen_string_literal: true

module Groups
  class CreateOrUpdateBatchService < BaseService
    def initialize(billable_metric:, group_params:)
      @billable_metric = billable_metric
      @group_params = group_params

      super
    end

    def call
      if group_params.empty?
        billable_metric.groups.discard_all
        return result
      end

      return result.validation_failure!(errors: { group: %w[value_is_invalid] }) unless valid_format?

      ActiveRecord::Base.transaction do
        if one_dimension?
          assign_groups(group_params[:key], group_params[:values].uniq)
        else
          billable_metric.groups.parents.where.not(value: group_params[:values].map { |v| v[:name] }).discard_all

          group_params[:values].each do |value|
            parent_group = billable_metric.groups.find_or_create_by!(key: group_params[:key], value: value[:name])
            assign_groups(value[:key], value[:values].uniq, parent_group.id)
          end
        end
      end

      draft_ids = Invoice.draft.joins(plans: [:billable_metrics])
        .where(billable_metrics: { id: billable_metric.id }).distinct.pluck(:id)
      Invoices::RefreshBatchJob.perform_later(draft_ids) if draft_ids.present?

      result
    end

    private

    attr_reader :billable_metric, :group_params

    # One dimension:
    # { key: "region", values: ["USA", "EUROPE"] }
    #
    # Two dimensions:
    # {
    #   key: "region",
    #   values: [{
    #     name: "Africa",
    #   	key: "cloud",
    #     values: ["Google cloud", "AWS", "Qovery", "Cloudfare"]
    #   }, {
    #     name: "America",
    #   	key: "cloud",
    #     values: ["Google cloud", "AWS"]
    #   }]
    # }
    def valid_format?
      return false unless group_params[:key].is_a?(String) && group_params[:values].is_a?(Array)
      return true if one_dimension?
      return false unless group_params[:values].all?(Hash)

      group_params[:values].map { |e| [e[:name], e[:key], e[:values]] }.flatten.all?(String)
    end

    def assign_groups(key, values, parent_group_id = nil)
      groups_to_discard = billable_metric.groups.where.not(key:, value: values)
      groups_to_discard = groups_to_discard.where(parent_group_id:).children if parent_group_id
      groups_to_discard.discard_all

      values.each do |value|
        next if billable_metric.groups.find_by(key:, value:, parent_group_id:)

        discarded = billable_metric.groups.with_discarded.discarded.find_by(key:, value:, parent_group_id:)
        if discarded
          discarded.undiscard!
          next
        end

        billable_metric.groups.create!(key:, value:, parent_group_id:)
      end
    end

    def one_dimension?
      # ie: { key: "region", values: ["USA", "EUROPE"] }
      group_params[:key].is_a?(String) && group_params[:values]&.all?(String)
    end
  end
end
