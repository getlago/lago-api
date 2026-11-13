# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApiLoggable do
  # rubocop:disable RSpec/DescribedClass
  controller(ApplicationController) do
    include ApiLoggable

    attr_reader :current_organization

    def index
      render json: :ok
    end
  end
  # rubocop:enable RSpec/DescribedClass

  before do
    allow(Utils::ApiLog).to receive(:produce)
  end

  context "when get" do
    it "does not produce api log" do
      get :index

      expect(Utils::ApiLog).not_to have_received(:produce)
    end
  end

  [:post, :put, :delete].each do |method|
    context "when method is #{method}" do
      it "produces api log" do
        send(method, :index)

        expect(Utils::ApiLog).to have_received(:produce)
      end
    end
  end

  context "without filter_audit_log_params!" do
    it "produces api log with no filtered params" do
      post :index

      expect(Utils::ApiLog).to have_received(:produce)
        .with(anything, anything, organization: nil, filtered_params: [], filtered_response: [])
    end
  end

  context "with filter_audit_log_params!" do
    # rubocop:disable RSpec/DescribedClass
    controller(ApplicationController) do
      include ApiLoggable

      filter_audit_log_params! :secret_field

      attr_reader :current_organization

      def index
        render json: :ok
      end
    end
    # rubocop:enable RSpec/DescribedClass

    it "produces api log with the filtered params" do
      post :index

      expect(Utils::ApiLog).to have_received(:produce)
        .with(anything, anything, organization: nil, filtered_params: [:secret_field], filtered_response: [])
    end
  end

  context "with filter_audit_log_response!" do
    # rubocop:disable RSpec/DescribedClass
    controller(ApplicationController) do
      include ApiLoggable

      filter_audit_log_response! :secret_field

      attr_accessor :current_organization

      def index
        render json: {item: {secret_field: "secret-value", other_field: "visible"}}
      end
    end
    # rubocop:enable RSpec/DescribedClass

    it "produces api log with the filtered response keys" do
      post :index

      expect(Utils::ApiLog).to have_received(:produce)
        .with(anything, anything, organization: nil, filtered_params: [], filtered_response: [:secret_field])
    end

    context "when the API log is sent to Kafka", :capture_kafka_messages do
      include_context "with API log infrastructure"

      let(:organization) { create(:organization) }

      before do
        # Utils::ApiLog reads the API version from the path.
        routes.draw { post "api/v1/items" => "anonymous#index" }
        allow(Utils::ApiLog).to receive(:produce).and_call_original
        controller.current_organization = organization
      end

      it "masks the filtered keys of the logged response" do
        post :index

        expect(api_log_payload["request_response"]).to eq(
          "item" => {"secret_field" => "[FILTERED]", "other_field" => "visible"}
        )
      end
    end
  end

  context "with skip_audit_logs!" do
    # rubocop:disable RSpec/DescribedClass
    controller(ApplicationController) do
      include ApiLoggable

      skip_audit_logs!

      def index
        render json: :ok
      end
    end
    # rubocop:enable RSpec/DescribedClass

    [:get, :post, :put, :delete].each do |method|
      context "when method is #{method}" do
        it "does not produce api log" do
          send(method, :index)

          expect(Utils::ApiLog).not_to have_received(:produce)
        end
      end
    end
  end
end
