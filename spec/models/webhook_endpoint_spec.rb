# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhookEndpoint do
  it { is_expected.to belong_to(:organization) }
  it { is_expected.to have_many(:webhooks).dependent(:delete_all) }
  it { is_expected.to have_many(:signing_keys).class_name("WebhookEndpointSigningKey").dependent(:delete_all) }
  it { is_expected.to have_many(:usable_signing_keys).class_name("WebhookEndpointSigningKey") }

  it { is_expected.to validate_presence_of(:webhook_url) }

  it { is_expected.to define_enum_for(:signature_algo).validating.with_values(jwt: 0, hmac: 1, standard_webhooks: 2) }

  describe "validations" do
    subject(:webhook_endpoint) { build(:webhook_endpoint) }

    describe "of webhook url uniqueness" do
      let(:errors) { webhook_endpoint.errors }

      context "when it is unique in scope of organization" do
        it "does not add an error" do
          expect(errors.where(:webhook_url, :taken)).not_to be_present
        end
      end

      context "when it not is unique in scope of organization" do
        subject(:webhook_endpoint) do
          build(:webhook_endpoint, organization:, webhook_url: organization.webhook_endpoints.first.webhook_url)
        end

        let(:organization) { create(:organization) }
        let(:errors) { webhook_endpoint.errors }

        before { webhook_endpoint.valid? }

        it "adds an error" do
          expect(errors.where(:webhook_url, :taken)).to be_present
        end
      end
    end

    context "when http webhook url is valid" do
      before { webhook_endpoint.webhook_url = "http://foo.bar" }

      it "is valid" do
        expect(webhook_endpoint).to be_valid
      end
    end

    context "when https webhook url is valid" do
      before { webhook_endpoint.webhook_url = "https://foo.bar" }

      it "is valid" do
        expect(webhook_endpoint).to be_valid
      end
    end

    context "when webhook url is invalid" do
      before { webhook_endpoint.webhook_url = "foobar" }

      it "is invalid" do
        expect(webhook_endpoint).not_to be_valid
      end
    end

    describe "signature_algo validation" do
      subject(:webhook_endpoint) { build(:webhook_endpoint, organization:, signature_algo:) }

      let(:organization) { create(:organization) }

      context "when the organization has neither the product catalog nor the rollout flag" do
        %w[jwt hmac].each do |algo|
          context "with #{algo}" do
            let(:signature_algo) { algo }

            it { is_expected.to be_valid }
          end
        end

        context "with standard_webhooks" do
          let(:signature_algo) { "standard_webhooks" }

          it "is invalid" do
            expect(webhook_endpoint).not_to be_valid
            expect(webhook_endpoint.errors.details[:signature_algo]).to eq([{error: :inclusion}])
            expect(webhook_endpoint.errors.messages[:signature_algo]).to eq(["value_is_invalid"])
          end
        end
      end

      context "when the organization has the standard_webhooks_signature flag" do
        let(:organization) { create(:organization, feature_flags: ["standard_webhooks_signature"]) }

        %w[jwt hmac standard_webhooks].each do |algo|
          context "with #{algo}" do
            let(:signature_algo) { algo }

            it { is_expected.to be_valid }
          end
        end
      end

      context "when the organization has the product catalog" do
        let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }

        context "with standard_webhooks" do
          let(:signature_algo) { "standard_webhooks" }

          it { is_expected.to be_valid }
        end

        %w[jwt hmac].each do |algo|
          context "with #{algo}" do
            let(:signature_algo) { algo }

            it "is invalid" do
              expect(webhook_endpoint).not_to be_valid
              expect(webhook_endpoint.errors.messages[:signature_algo]).to eq(["value_is_invalid"])
            end
          end
        end

        context "when an existing endpoint keeps an algorithm the organization no longer allows" do
          subject(:webhook_endpoint) { create(:webhook_endpoint, :legacy_signature_algo, organization:, signature_algo: :jwt) }

          it "can still be updated" do
            expect(webhook_endpoint.update(name: "Renamed")).to be(true)
          end

          it "cannot switch to another refused algorithm" do
            expect(webhook_endpoint.update(signature_algo: :hmac)).to be(false)
            expect(webhook_endpoint.errors.messages[:signature_algo]).to eq(["value_is_invalid"])
          end
        end
      end

      [["an unknown value", "md5"], ["nil", nil]].each do |label, value|
        context "with #{label}" do
          let(:signature_algo) { value }

          it "has a single value_is_invalid error" do
            expect(webhook_endpoint).not_to be_valid
            expect(webhook_endpoint.errors.messages[:signature_algo]).to eq(["value_is_invalid"])
          end
        end
      end
    end

    describe "event_type validity" do
      context "when nil" do
        before { webhook_endpoint.event_types = nil }

        it "is valid" do
          expect(webhook_endpoint).to be_valid
        end
      end

      context "when an empty array" do
        before { webhook_endpoint.event_types = [] }

        it "is valid" do
          expect(webhook_endpoint).to be_valid
        end
      end

      context "when not an array" do
        before { webhook_endpoint.event_types = "not_an_array" }

        it "is not valid" do
          expect(webhook_endpoint).not_to be_valid
        end
      end

      context "when contains valid types" do
        before { webhook_endpoint.event_types = ["customer.updated"] }

        it "is valid" do
          expect(webhook_endpoint).to be_valid
        end
      end

      context "when contains invalid types" do
        before { webhook_endpoint.event_types = ["invalid.event"] }

        it "is not valid" do
          expect(webhook_endpoint).not_to be_valid
        end
      end
    end
  end

  describe ".validation_codes" do
    subject(:codes) { described_class.validation_codes(webhook_endpoint.errors) }

    let(:webhook_endpoint) { build(:webhook_endpoint, webhook_url: "foobar", event_types: ["wrong.type"]) }

    before { webhook_endpoint.valid? }

    it "replaces the sentences with a token and keeps the codes" do
      expect(webhook_endpoint.errors.messages).to eq(
        webhook_url: ["url_is_invalid"],
        event_types: ["contains invalid types: [\"wrong.type\"]"]
      )
      expect(codes).to eq(webhook_url: ["url_is_invalid"], event_types: ["value_is_invalid"])
    end
  end

  describe "#allowed_signature_algos" do
    subject(:allowed_signature_algos) { build(:webhook_endpoint, organization:).allowed_signature_algos }

    let(:organization) { create(:organization) }

    it "returns jwt and hmac without the rollout flag" do
      expect(allowed_signature_algos).to eq(%w[jwt hmac])
    end

    context "when the organization has the standard_webhooks_signature flag" do
      let(:organization) { create(:organization, feature_flags: ["standard_webhooks_signature"]) }

      it "returns the three algorithms" do
        expect(allowed_signature_algos).to eq(%w[jwt hmac standard_webhooks])
      end
    end

    context "when the organization has the product catalog" do
      let(:organization) { create(:organization, feature_flags: ["product_catalog", "standard_webhooks_signature"]) }

      it "returns only standard_webhooks, even with the rollout flag" do
        expect(allowed_signature_algos).to eq(%w[standard_webhooks])
      end
    end
  end

  describe "#active_signing_keys" do
    subject(:active_signing_keys) { webhook_endpoint.active_signing_keys }

    let(:webhook_endpoint) { create(:webhook_endpoint, :legacy_signature_algo, signature_algo: :standard_webhooks) }
    let(:newer_key) { create(:webhook_endpoint_signing_key, webhook_endpoint:, created_at: 1.day.ago) }
    let(:older_key) { create(:webhook_endpoint_signing_key, webhook_endpoint:, created_at: 2.days.ago) }

    before do
      freeze_time

      newer_key
      older_key
      create(:webhook_endpoint_signing_key, webhook_endpoint:, expires_at: 1.minute.ago)
    end

    it "returns the usable keys, oldest first" do
      expect(active_signing_keys).to eq([older_key, newer_key])
    end

    context "when the endpoint signs with jwt and kept keys from a former switch" do
      let(:webhook_endpoint) { create(:webhook_endpoint, signature_algo: :jwt) }

      it "returns no key" do
        expect(active_signing_keys).to be_empty
      end
    end
  end

  describe ".default_signature_algo" do
    subject(:default_signature_algo) { described_class.default_signature_algo(organization) }

    let(:organization) { build(:organization) }

    it "returns jwt" do
      expect(default_signature_algo).to eq("jwt")
    end

    context "when the organization has the product catalog" do
      let(:organization) { build(:organization, feature_flags: ["product_catalog"]) }

      it "returns standard_webhooks" do
        expect(default_signature_algo).to eq("standard_webhooks")
      end
    end
  end

  describe ".validation_meta" do
    subject(:validation_meta) { described_class.validation_meta(webhook_endpoint, {webhook_url: {max_length: 10}}) }

    let(:organization) { create(:organization) }
    let(:webhook_endpoint) { build(:webhook_endpoint, organization:, signature_algo: :standard_webhooks) }

    before { webhook_endpoint.valid? }

    it "adds the algorithms the organization allows to the given meta" do
      expect(validation_meta).to eq(webhook_url: {max_length: 10}, signature_algo: {allowed_values: %w[jwt hmac]})
    end

    context "when the signature_algo has no error" do
      let(:webhook_endpoint) { build(:webhook_endpoint, organization:, signature_algo: :hmac) }

      it "returns the given meta" do
        expect(validation_meta).to eq(webhook_url: {max_length: 10})
      end
    end
  end

  describe "callbacks" do
    describe "#normalize_event_types" do
      subject(:webhook_endpoint) { build(:webhook_endpoint, event_types:) }

      context "when event_types contains duplicates, blanks, mixed case and whitespaces" do
        let(:event_types) {
          [
            " Customer.Created ",
            "invoice.drafted ",
            " Invoice.DRAFTED",
            nil,
            "  ",
            ""
          ]
        }

        it "normalizes the event types" do
          webhook_endpoint.valid?
          expect(webhook_endpoint).to be_valid
          expect(webhook_endpoint.event_types).to eq(["customer.created", "invoice.drafted"])
        end
      end

      context "when event_types contains a renamed event type" do
        let(:event_types) { ["invoice.drafted", "credit_note.provider_refund_failure"] }

        it "replaces it with its current name" do
          webhook_endpoint.valid?
          expect(webhook_endpoint).to be_valid
          expect(webhook_endpoint.event_types).to eq(["invoice.drafted", "credit_note.refund_failure"])
        end
      end

      context "when event_types is nil" do
        let(:event_types) { nil }

        it "does not change event_types" do
          webhook_endpoint.valid?
          expect(webhook_endpoint).to be_valid
          expect(webhook_endpoint.event_types).to be_nil
        end
      end

      context "when event_types contains *" do
        let(:event_types) { ["*"] }

        it "sets event_types to nil" do
          webhook_endpoint.valid?
          expect(webhook_endpoint).to be_valid
          expect(webhook_endpoint.event_types).to be_nil
        end
      end

      context "when event_types contains * and other values" do
        let(:event_types) { ["*", "customer.created"] }

        it "does not change event_types" do
          webhook_endpoint.valid?
          expect(webhook_endpoint).not_to be_valid
          expect(webhook_endpoint.event_types).to eq(["*", "customer.created"])
        end
      end
    end
  end

  describe "constants" do
    describe "WEBHOOK_EVENT_TYPES" do
      it "matches configured event names to registered webhook handlers" do
        event_types = YAML.safe_load_file(Rails.root.join("config/webhook_event_types.yml")).values
        documented_types = event_types.map { |event| event.fetch("name") }
        product_catalog_types = event_types.filter_map do |event|
          event.fetch("name") if event["product_catalog_only"]
        end
        handler_types = SendWebhookJob::WEBHOOK_SERVICES.keys

        expect(handler_types.sort).to eq(documented_types.sort)

        resource_namespaces = {
          "product_category" => Webhooks::ProductCategories,
          "product" => Webhooks::Products,
          "product_filter" => Webhooks::ProductFilters,
          "rate_card" => Webhooks::RateCards,
          "rate_card_rate" => Webhooks::RateCardRates,
          "plan_rate_card" => Webhooks::PlanRateCards,
          "contract_rate_card" => Webhooks::ContractRateCards,
          "contract" => Webhooks::Contracts
        }

        expected_mappings = product_catalog_types.to_h do |event_type|
          resource, action = event_type.split(".")
          service_class = resource_namespaces.fetch(resource).const_get("#{action.camelize}Service")
          [event_type, service_class]
        end

        expect(SendWebhookJob::WEBHOOK_SERVICES.slice(*product_catalog_types)).to eq(expected_mappings)
      end

      it "matches the webhook_type each handler delivers" do
        delivered_types = SendWebhookJob::WEBHOOK_SERVICES.transform_values do |service|
          service.new(object: nil).send(:webhook_type)
        end

        expect(delivered_types).to eq(SendWebhookJob::WEBHOOK_SERVICES.to_h { |type, _| [type, type] })
      end
    end
  end

  describe "product catalog event type validation" do
    subject(:webhook_endpoint) { build(:webhook_endpoint, event_types:) }

    context "when selecting a documented product catalog event" do
      let(:event_types) { ["product.created"] }

      it "is valid regardless of catalog feature enablement" do
        expect(webhook_endpoint).to be_valid
      end
    end

    context "when selecting an unknown event" do
      let(:event_types) { ["product.unknown"] }

      it "is invalid" do
        expect(webhook_endpoint).not_to be_valid
      end
    end
  end
end
