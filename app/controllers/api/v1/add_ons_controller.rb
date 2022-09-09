# frozen_string_literal: true

module Api
  module V1
    class AddOnsController < Api::BaseController
      def create
        service = AddOns::CreateService.new
        result = service.create(
          **input_params
            .merge(organization_id: current_organization.id)
            .to_h
            .symbolize_keys,
        )

        if result.success?
          render_add_on(result.add_on)
        else
          validation_errors(result)
        end
      end

      def update
        service = AddOns::UpdateService.new
        result = service.update_from_api(
          organization: current_organization,
          code: params[:code],
          params: input_params,
        )

        if result.success?
          render_add_on(result.add_on)
        else
          render_error_response(result)
        end
      end

      def destroy
        service = AddOns::DestroyService.new
        result = service.destroy_from_api(
          organization: current_organization,
          code: params[:code],
        )

        if result.success?
          render_add_on(result.add_on)
        else
          render_error_response(result)
        end
      end

      def show
        add_on = current_organization.add_ons.find_by(
          code: params[:code],
        )

        return not_found_error(message: 'add_on_not_found') unless add_on

        render_add_on(add_on)
      end

      def index
        add_ons = current_organization.add_ons
          .order(created_at: :desc)
          .page(params[:page])
          .per(params[:per_page] || PER_PAGE)

        render(
          json: ::CollectionSerializer.new(
            add_ons,
            ::V1::AddOnSerializer,
            collection_name: 'add_ons',
            meta: pagination_metadata(add_ons),
          ),
        )
      end

      private

      def input_params
        params.require(:add_on).permit(
          :name,
          :code,
          :amount_cents,
          :amount_currency,
          :description,
        )
      end

      def render_add_on(add_on)
        render(
          json: ::V1::AddOnSerializer.new(
            add_on,
            root_name: 'add_on',
          ),
        )
      end
    end
  end
end
