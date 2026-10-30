# frozen_string_literal: true

module Api
  module V1
    module DataApi
      class BaseController < Api::V1::BaseController
        private

        def resource_name
          "analytic"
        end
      end
    end
  end
end
