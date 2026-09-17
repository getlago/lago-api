# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::RequiresProductCatalog do
  include ApiHelper

  # rubocop:disable RSpec/DescribedClass
  controller(ApplicationController) do
    include ApiErrors
    include Api::RequiresProductCatalog

    attr_reader :current_organization

    def index
      render json: {ok: true}
    end
  end
  # rubocop:enable RSpec/DescribedClass

  let(:organization) { create(:organization, feature_flags:) }
  let(:feature_flags) { [] }

  before { allow(controller).to receive(:current_organization).and_return(organization) }

  context "when the organization is not on the product catalog" do
    it "returns a forbidden error" do
      get :index

      expect(response).to have_http_status(:forbidden)
      expect(json[:code]).to eq("feature_unavailable")
    end
  end

  context "when the organization is on the product catalog", :premium do
    let(:feature_flags) { ["product_catalog"] }

    it "allows the request" do
      get :index

      expect(response).to have_http_status(:success)
      expect(json[:ok]).to be(true)
    end
  end
end
