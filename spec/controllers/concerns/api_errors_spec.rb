# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApiErrors, type: :controller do
  describe "#validation_errors" do
    context "with simple errors" do
      controller(ApplicationController) do
        include ApiErrors # rubocop:disable RSpec/DescribedClass

        def index
          result = BaseService::LegacyResult.new.validation_failure!(
            errors: {field_name: ["error_1", :error_2]}
          )
          render_error_response(result)
        end
      end

      it "returns error_details and meta" do
        response = get :index

        expect(response).to have_http_status(:unprocessable_entity)

        body = JSON.parse(response.body)
        expect(body["error_details"]).to eq({"field_name" => ["error_1", "error_2"]})
        expect(body["metadata"]).to eq([
          {"field" => "field_name", "code" => "error_1"},
          {"field" => "field_name", "code" => "error_2"}
        ])
      end
    end

    context "with errors including metadata" do
      controller(ApplicationController) do
        include ApiErrors # rubocop:disable RSpec/DescribedClass

        def index
          result = BaseService::LegacyResult.new.validation_failure!(
            errors: {
              field_name: [
                {"code" => :error_1, :yolo => true},
                {:code => "error_2", "count" => 100}
              ]
            }
          )
          render_error_response(result)
        end
      end

      it "returns error_details and meta" do
        response = get :index

        expect(response).to have_http_status(:unprocessable_entity)

        body = JSON.parse(response.body)
        expect(body["error_details"]).to eq({"field_name" => ["error_1", "error_2"]})
        expect(body["metadata"]).to eq([
          {"field" => "field_name", "code" => "error_1", "yolo" => true},
          {"field" => "field_name", "code" => "error_2", "count" => 100}
        ])
      end
    end
  end
end
