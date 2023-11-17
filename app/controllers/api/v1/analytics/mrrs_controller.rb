# frozen_string_literal: true

module Api
  module V1
    module Analytics
      class MrrsController < Api::BaseController
        def index
          result = ::Analytics::MrrsService.new(current_organization, **filters).call

          if result.success?
            render_result(result.records)
          else
            render_error_response(result)
          end
        end

        private

        def render_result(records)
          render(
            json: ::CollectionSerializer.new(
              records,
              ::V1::Analytics::MrrSerializer,
              collection_name: 'mrrs',
            ),
          )
        end

        def filters
          {
            currency: params[:currency]&.upcase,
            months: params[:months].to_i,
          }
        end
      end
    end
  end
end
