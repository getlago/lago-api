# frozen_string_literal: true

module Api
  # An /api/v2 path that no route serves, in the v2 body. Outside app/controllers/api/v2: it neither
  # authenticates nor belongs to the product catalog, so an unknown path is a 404 whatever the key.
  class UnknownV2RoutesController < ApplicationController
    include Api::V2Errors

    def show
      response.set_header("X-Lago-Endpoint-Status", "beta")
      not_found
    end
  end
end
