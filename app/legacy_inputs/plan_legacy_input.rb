# frozen_string_literal: true

class PlanLegacyInput < BaseLegacyInput
  def create_input
    return args unless args[:charges].is_a?(Array)
    return args unless args[:charges].any? { |c| c[:group_properties].present? }

    args[:charges].each do |charge|
      next if charge[:group_properties].blank?
      next charge[:group] = [] if charge[:filters].present?

      billable_metric = organization.billable_metrics.find_by(id: charge[:billable_metric_id])
      next unless billable_metric

      charge[:filters] = charge[:group_properties].map do |properties|
        group = billable_metric.groups.find_by(id: properties[:group_id])
        next unless group

        values = {group.key => [group.value]}
        values[group.parent.key] = [group.parent.value] if group.parent

        {
          invoice_display_name: properties[:invoice_display_name],
          properties: properties[:values],
          values:
        }
      end

      # NOTE: create default filter to keep compatibility with old charges
      group_ids = charge[:group_properties].map { |p| p[:group_id] }

      billable_metric.groups.where.not(id: group_ids).includes(:children).find_each do |group|
        next if group.children.any?

        values = {group.key => [group.value]}
        values[group.parent.key] = [group.parent.value] if group.parent

        charge[:filters] << {
          properties: charge[:properties],
          values:
        }
      end
    end

    args
  end

  alias_method :update_input, :create_input
end
