# frozen_string_literal: true

module Public
  module V1
    class PermissionsController < BaseController
      def index
        render json: {
          permissions: Permission::DEFAULT_ROLE_TABLE
        }
      end
    end
  end
end
