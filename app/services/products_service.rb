# frozen_string_literal: true

class ProductsService < BaseService
  include ScopedToOrganization

  def create(**args)
    return result.fail!('not_organization_member') unless organization_member?(args[:organization_id])

    product = Product.new(
      organization_id: args[:organization_id],
      name: args[:name]
    )

    # Validates billable metrics
    metric_ids = args[:billable_metric_ids]
    if metric_ids.present? && product.organization.billable_metrics.where(id: metric_ids).count != metric_ids.count
      return result.fail!('unprocessable_entity', 'Billable metrics does not exists')
    end

    ActiveRecord::Base.transaction do
      # TODO: better handling of validation errors
      product.billable_metric_ids = metric_ids if metric_ids.present?
      product.save!
    end

    result.product = product
    result
  end
end
