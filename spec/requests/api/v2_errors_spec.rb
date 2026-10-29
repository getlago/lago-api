# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2Errors do
  # The id names the failure that the action renders.
  subject(:show) { get_with_token(organization, "/api/v2/error_tests/#{failure}") }

  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:failure) { "not_found" }

  # A v2 controller of the test's own, drawn on routes of its own for each example.
  around do |example|
    with_routing do |routes|
      routes.draw do
        namespace :api do
          namespace :v2 do
            resources :error_tests, only: %i[show create] do
              collection do
                get :out_of_range
                get :invalid_request
                get :missing_record
              end
            end
          end
        end
      end

      example.run
    end
  end

  before do
    # Each renderer is reached through its real caller: render_error_response, the rescues of
    # the base controllers, and the 400 helper.
    stub_const("Api::V2::ErrorTestsController", Class.new(Api::V2::BaseController) do
      def show
        render_error_response(failed_result)
      end

      def create
        params.require(:error_test)
        head(:ok)
      end

      def out_of_range
        raise ActiveModel::RangeError, "out of range"
      end

      def missing_record
        raise ActiveRecord::RecordNotFound
      end

      def invalid_request
        invalid_request_error(code: "invalid_expand", error_details: {expands: {invalid_values: ["fees"], allowed_values: []}, after: {reason: "malformed"}})
      end

      private

      def failed_result
        result = BaseService::Result.new

        case params[:id]
        when "not_found" then result.not_found_failure!(resource: "product")
        when "not_allowed" then result.not_allowed_failure!(code: "not_voidable")
        # Not the default code, which the catalog gate also renders.
        when "forbidden" then result.forbidden_failure!(code: "premium_integration_missing")
        when "provider_unauthorized"
          result.provider_unauthorized_failure!(provider: PaymentProviders::StripeProvider.new(code: "stripe_eu"), message: "Stripe authentication failed.")
        when "unauthorized" then result.unauthorized_failure!(message: "Session expired.")
        when "third_party"
          result.third_party_failure!(third_party: "Stripe", error_code: "resource_missing", error_message: "No such customer: 'cus_unknown'")
        when "provider"
          error = Stripe::CardError.new("Your card was declined.", nil, code: "card_declined")
          result.provider_failure!(provider: PaymentProviders::StripeProvider.new(code: "stripe_eu"), error:)
        when "third_party_status"
          result.third_party_failure!(third_party: "Cashfree", error_code: "400", error_message: "Bad Request")
        when "provider_without_code"
          result.provider_failure!(provider: PaymentProviders::StripeProvider.new(code: "stripe_eu"), error: StandardError.new("timeout"))
        # A Symbol, as throttle! names the provider.
        when "too_many_requests"
          result.too_many_provider_requests_failure!(provider_name: :anrok, error: BaseService::ThrottlingError.new(provider_name: :anrok))
        when "lock" then result.lock_acquisition_failure!(message: "lock")
        when "service" then result.service_failure!(code: "unknown", message: "unknown")
        when "validation"
          # Symbol keys, a dotted one included, and a string key: services pass both.
          result.validation_failure!(errors: {
            :name => ["value_is_mandatory"],
            :"rates.rate_properties" => %w[invalid_amount invalid_amount],
            :base => ["value_is_out_of_range"],
            "code" => ["value_already_exist"]
          })
        # A sentence, as a contract or Rails gives one, and an indexed hash of them.
        when "validation_with_sentences"
          result.validation_failure!(errors: {
            net_payment_term: ["is not a number"],
            account_type: {0 => ["must be one of: customer, partner"]},
            "rates.rate_properties": [:invalid_amount, "invalidAmount"],
            name: ["value_is_mandatory"]
          })
        when "validation_with_meta"
          result.single_validation_failure!(field: :position, error_code: "value_is_out_of_range", meta: {min: 1, max: 3})
        when "record_validation_with_meta"
          record = Customer.new
          record.errors.add(:currency, :inclusion, meta: {allowed_values: %w[EUR USD]})
          record.errors.add(:external_id, :blank)
          result.record_validation_failure!(record:)
        end
      end

      def resource_name
        "product"
      end
    end)
  end

  context "without an Authorization header" do
    subject(:show) { get("/api/v2/error_tests/#{failure}") }

    it "returns an unauthorized error without the reason phrase" do
      show

      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq(code: "unauthorized", details: [])
    end
  end

  context "when the organization is not on the product catalog" do
    let(:organization) { create(:organization) }

    it "returns a forbidden error" do
      show

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq(code: "feature_unavailable", details: [])
    end
  end

  context "with a forbidden failure" do
    let(:failure) { "forbidden" }

    it "returns a forbidden error with the code of the failure" do
      show

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq(code: "premium_integration_missing", details: [])
    end
  end

  context "with a provider unauthorized failure" do
    let(:failure) { "provider_unauthorized" }

    it "returns an unprocessable provider unauthorized error naming the provider, apart from an invalid API key" do
      show

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq(
        code: "provider_unauthorized",
        details: [{code: "provider_unauthorized", field: "base", meta: {provider_name: "stripe", provider_code: "stripe_eu"}}]
      )
    end
  end

  context "with an unauthorized failure that no provider raised" do
    let(:failure) { "unauthorized" }

    it "returns an unauthorized error without the message" do
      show

      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq(code: "unauthorized", details: [])
    end
  end

  context "with a third party failure" do
    let(:failure) { "third_party" }

    it "returns a provider error naming the third party and its error code, without its message" do
      show

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq(
        code: "provider_error",
        details: [{code: "provider_error", field: "base", meta: {provider_name: "stripe", provider_error_code: "resource_missing"}}]
      )
    end
  end

  context "with a provider failure" do
    let(:failure) { "provider" }

    it "returns a provider error naming the provider, its connection and its error code, without its message" do
      show

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq(
        code: "provider_error",
        details: [{
          code: "provider_error",
          field: "base",
          meta: {provider_name: "stripe", provider_code: "stripe_eu", provider_error_code: "card_declined"}
        }]
      )
    end
  end

  context "with a third party failure whose error code is an HTTP status" do
    let(:failure) { "third_party_status" }

    it "returns a provider error without the status as its error code" do
      show

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq(code: "provider_error", details: [{code: "provider_error", field: "base", meta: {provider_name: "cashfree"}}])
    end
  end

  context "with a provider failure whose error has no code" do
    let(:failure) { "provider_without_code" }

    it "returns a provider error without an error code" do
      show

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq(code: "provider_error", details: [{code: "provider_error", field: "base", meta: {provider_name: "stripe", provider_code: "stripe_eu"}}])
    end
  end

  context "with a too many provider requests failure" do
    let(:failure) { "too_many_requests" }

    it "returns a too many requests error naming the provider, without its message" do
      show

      expect(response).to have_http_status(:too_many_requests)
      expect(json).to eq(code: "too_many_provider_requests", details: [{code: "too_many_provider_requests", field: "base", meta: {provider_name: "anrok"}}])
    end
  end

  context "with a not found failure" do
    it "returns a not found error naming the resource in its meta" do
      show

      expect(response).to have_http_status(:not_found)
      expect(json).to eq(code: "resource_not_found", details: [{code: "resource_not_found", field: "base", meta: {resource: "product"}}])
    end
  end

  context "with a record that no lookup names" do
    subject(:missing_record) { get_with_token(organization, "/api/v2/error_tests/missing_record") }

    it "returns a not found error without an entry" do
      missing_record

      expect(response).to have_http_status(:not_found)
      expect(json).to eq(code: "resource_not_found", details: [])
    end
  end

  context "with a not allowed failure" do
    let(:failure) { "not_allowed" }

    it "returns an unprocessable error with the code of the failure" do
      show

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq(code: "not_voidable", details: [])
    end
  end

  context "with a validation failure" do
    let(:failure) { "validation" }

    it "returns one entry per code, in order and duplicates kept" do
      show

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq(
        code: "validation_errors",
        details: [
          {code: "value_is_mandatory", field: "name", meta: {}},
          {code: "invalid_amount", field: "rates.rate_properties", meta: {}},
          {code: "invalid_amount", field: "rates.rate_properties", meta: {}},
          {code: "value_is_out_of_range", field: "base", meta: {}},
          {code: "value_already_exist", field: "code", meta: {}}
        ]
      )
    end
  end

  context "with a validation failure whose codes are not tokens" do
    let(:failure) { "validation_with_sentences" }

    it "raises in development and test" do
      expect { show }.to raise_error(ArgumentError, "code of net_payment_term is not a token: String")
    end

    context "when the environment is not local" do
      before do
        allow(Rails.env).to receive(:local?).and_return(false)
        allow(Sentry).to receive(:capture_exception)
      end

      it "returns value_is_invalid in their place and reports each one" do
        show

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(
          code: "validation_errors",
          details: [
            {code: "value_is_invalid", field: "net_payment_term", meta: {}},
            {code: "value_is_invalid", field: "account_type", meta: {}},
            {code: "invalid_amount", field: "rates.rate_properties", meta: {}},
            {code: "value_is_invalid", field: "rates.rate_properties", meta: {}},
            {code: "value_is_mandatory", field: "name", meta: {}}
          ]
        )
        expect(Sentry).to have_received(:capture_exception).exactly(3).times
        expect(Sentry).to have_received(:capture_exception)
          .with(an_object_having_attributes(message: "code of account_type is not a token: Hash"))
        expect(Sentry).to have_received(:capture_exception)
          .with(an_object_having_attributes(message: "code of rates.rate_properties is not a token: String"))
      end
    end
  end

  context "with a validation failure carrying meta" do
    let(:failure) { "validation_with_meta" }

    it "returns the meta of the code" do
      show

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq(code: "validation_errors", details: [{code: "value_is_out_of_range", field: "position", meta: {min: 1, max: 3}}])
    end
  end

  context "with a record whose errors carry meta" do
    let(:failure) { "record_validation_with_meta" }

    it "returns the meta option of each error, and an empty object for an error without" do
      show

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq(
        code: "validation_errors",
        details: [
          {code: "value_is_invalid", field: "currency", meta: {allowed_values: %w[EUR USD]}},
          {code: "value_is_mandatory", field: "external_id", meta: {}}
        ]
      )
    end
  end

  context "with a lock acquisition failure" do
    let(:failure) { "lock" }

    it "returns a concurrency conflict without the message" do
      show

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq(code: "validation_errors", details: [{code: "concurrency_conflict", field: "base", meta: {}}])
    end
  end

  context "with a service failure" do
    let(:failure) { "service" }

    it "raises it, as v1 does" do
      expect { show }.to raise_error(BaseService::ServiceFailure)
    end
  end

  context "with a value out of range" do
    subject(:out_of_range) { get_with_token(organization, "/api/v2/error_tests/out_of_range") }

    it "returns a validation error on base" do
      out_of_range

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq(code: "validation_errors", details: [{code: "value_is_out_of_range", field: "base", meta: {}}])
    end
  end

  context "with a missing parameter" do
    subject(:create_request) { post_with_token(organization, "/api/v2/error_tests", {}) }

    it "returns a bad request error keyed by the parameter" do
      create_request

      expect(response).to have_http_status(:bad_request)
      expect(json).to eq(code: "missing_parameter", details: [{code: "missing", field: "error_test", meta: {}}])
    end
  end

  context "with an invalid request" do
    subject(:invalid_request) { get_with_token(organization, "/api/v2/error_tests/invalid_request") }

    it "returns one entry per parameter, the code of the error standing in for a missing reason" do
      invalid_request

      expect(response).to have_http_status(:bad_request)
      expect(json).to eq(
        code: "invalid_expand",
        details: [
          {code: "invalid_expand", field: "expands", meta: {invalid_values: ["fees"], allowed_values: []}},
          {code: "malformed", field: "after", meta: {}}
        ]
      )
    end
  end
end
