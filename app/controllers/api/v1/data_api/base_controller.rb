# frozen_string_literal: true

module Api
  module V1
    module DataApi
      class BaseController < Api::BaseController
        private

        def resource_name
          "analytic"
        end

        def render_result(result)
          # {"daily_usages" => result.daily_usages}.to_json
          render(json: {"daily_usages" => []}.to_json)
        end
      end
    end
  end
end
