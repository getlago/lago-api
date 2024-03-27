# frozen_string_literal: true

module Api
  module V1
    module BillableMetrics
      class GroupsController < Api::BaseController
        def index
          metric = current_organization.billable_metrics.find_by(code: params[:code])
          return not_found_error(resource: "billable_metric") unless metric

          groups = metric.selectable_groups
            .page(params[:page]).per(params[:per_page] || PER_PAGE)

          render(
            json: ::CollectionSerializer.new(
              groups,
              ::V1::GroupSerializer,
              collection_name: "groups",
              meta: pagination_metadata(groups)
            )
          )
        end
      end
    end
  end
end
