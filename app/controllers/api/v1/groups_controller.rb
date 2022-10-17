# frozen_string_literal: true

module Api
  module V1
    class GroupsController < Api::BaseController
      def index
        metric = current_organization.billable_metrics.find_by(id: params[:billable_metric_id])
        return not_found_error(resource: 'billable_metric') unless metric

        groups = metric.groups.active.children.page(params[:page]).per(params[:per_page] || PER_PAGE)

        render(
          json: ::CollectionSerializer.new(
            groups,
            ::V1::GroupSerializer,
            collection_name: 'groups',
            meta: pagination_metadata(groups),
          ),
        )
      end
    end
  end
end
