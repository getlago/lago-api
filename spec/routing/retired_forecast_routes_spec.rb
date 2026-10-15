# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Retired forecast routes" do
  it "routes forecast amount calculations to the not-found handler" do
    %w[
      /data_api/v1/charges/charge-id/forecasted_usage_amount
      /data_api/v1/charges/bulk_forecasted_usage_amount
    ].each do |path|
      recognized = Rails.application.routes.recognize_path(path, method: :post)

      expect(recognized.slice(:controller, :action)).to eq(controller: "application", action: "not_found")
    end
  end
end
