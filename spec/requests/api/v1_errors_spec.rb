# frozen_string_literal: true

require "rails_helper"

describe Api::V1Errors do
  subject(:show) { get_with_token(organization, "/api/v1/error_tests/#{failure}") }

  let(:organization) { create(:organization) }

  around do |example|
    with_routing do |routes|
      routes.draw do
        namespace :api do
          namespace :v1 do
            resources :error_tests, only: :show
          end
        end
      end

      example.run
    end
  end

  before do
    stub_const("Api::V1::ErrorTestsController", Class.new(Api::V1::BaseController) do
      def show
        result = BaseService::Result.new

        case params[:id]
        when "gone" then result.gone_failure!(code: "invoice_closed")
        when "conflict" then result.conflict_failure!(code: "payment_pending")
        end

        render_error_response(result)
      end

      private

      def resource_name
        "invoice"
      end
    end)
  end

  context "with a gone failure" do
    let(:failure) { "gone" }

    it "renders a 410 with the code of the failure" do
      show

      expect(response).to have_http_status(:gone)
      expect(json).to eq(status: 410, error: "Gone", code: "invoice_closed")
    end
  end

  context "with a conflict failure" do
    let(:failure) { "conflict" }

    it "renders a 409 with the code of the failure" do
      show

      expect(response).to have_http_status(:conflict)
      expect(json).to eq(status: 409, error: "Conflict", code: "payment_pending")
    end
  end
end
