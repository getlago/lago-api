# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Retired gRPC token route" do
  it "routes the gRPC token endpoint to the not-found handler" do
    %w[/api/v1/organizations/grpc_token /api/v2/organizations/grpc_token].each do |path|
      recognized = Rails.application.routes.recognize_path(path, method: :get)

      expect(recognized.slice(:controller, :action)).to eq(controller: "application", action: "not_found")
    end
  end
end
