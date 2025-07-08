# frozen_string_literal: true

class OrganizationIdCheckConstaintOnBillableMetricFilters < ActiveRecord::Migration[8.0]
  def change
    add_check_constraint :billable_metric_filters,
      "organization_id IS NOT NULL",
      name: "billable_metric_filters_organization_id_null",
      validate: false
  end
end
