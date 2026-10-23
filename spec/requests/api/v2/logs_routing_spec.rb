# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API v2 log routes" do
  # The native v2 log routes are drawn before the `namespace :v2, module: :v1`
  # fallback, so they win recognition. Asserting against the ordered route table
  # proves the precedence without loading the v2 controller classes, which other
  # tasks add.
  def first_get_route(path_prefix)
    Rails.application.routes.routes.find do |route|
      route.verb == "GET" && route.path.spec.to_s.start_with?(path_prefix)
    end
  end

  {
    "activity_logs" => :activity_id
  }.each do |resource, param|
    it "routes the #{resource} index to the native v2 controller" do
      route = first_get_route("/api/v2/#{resource}(")

      expect(route.defaults.slice(:controller, :action))
        .to eq(controller: "api/v2/#{resource}", action: "index")
    end

    it "routes the #{resource} show to the native v2 controller with the #{param} param" do
      route = first_get_route("/api/v2/#{resource}/:#{param}(")

      expect(route.defaults.slice(:controller, :action))
        .to eq(controller: "api/v2/#{resource}", action: "show")
    end
  end
end
