# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApiKeys::RotateService do
  include_context "with mocked security logger"

  describe "#call" do
    subject(:service_result) { described_class.call(api_key:, params:) }

    let(:params) { {expires_at:, name:} }
    let(:name) { Faker::Lorem.words.join(" ") }

    context "when API key is provided" do
      let!(:api_key) { create(:api_key) }
      let(:organization) { api_key.organization }

      context "when preferred expiration date is provided" do
        let(:expires_at) { generate(:future_date) }

        context "with premium organization", :premium do
          it "expires the API key with preferred date" do
            expect { service_result }
              .to change { api_key.reload.expires_at&.iso8601 }
              .to(expires_at.iso8601)
          end

          it "creates a new API key for organization" do
            expect { service_result }.to change(ApiKey, :count).by(1)

            expect(service_result.api_key)
              .to be_persisted.and have_attributes(organization:, name:)
          end

          it "sends an API key rotated email" do
            expect { service_result }
              .to have_enqueued_mail(ApiKeyMailer, :rotated).with hash_including(params: {api_key:})
          end

          it "produces a security log" do
            new_api_key = service_result.api_key

            expect(security_logger).to have_received(:produce).with(
              organization: organization,
              log_type: "api_key",
              log_event: "api_key.rotated",
              resources: {
                name: new_api_key.name,
                value_ending: {deleted: api_key.value.last(4), added: new_api_key.value.last(4)}
              }
            )
          end
        end

        context "with free organization" do
          it "does not creates a new API key for organization" do
            expect { service_result }.not_to change(ApiKey, :count)
          end

          it "does not send an API key rotated email" do
            expect { service_result }.not_to have_enqueued_mail(ApiKeyMailer, :rotated)
          end

          it "returns an error" do
            expect(service_result).not_to be_success
            expect(service_result.error).to be_a(BaseService::ForbiddenFailure)
            expect(service_result.error.code).to eq("cannot_rotate_with_provided_date")
          end

          it "does not produce a security log" do
            service_result

            expect(security_logger).not_to have_received(:produce)
          end
        end
      end

      context "when preferred expiration date is missing" do
        let(:expires_at) { nil }

        before { freeze_time }

        context "with premium organization", :premium do
          it "expires the API key with current time" do
            expect { service_result }.to change(api_key, :expires_at).to(Time.current)
          end

          it "creates a new API key for organization" do
            expect { service_result }.to change(ApiKey.unscoped, :count).by(1)

            expect(service_result.api_key)
              .to be_persisted.and have_attributes(organization:, name:)
          end

          it "sends an API key rotated email" do
            expect { service_result }
              .to have_enqueued_mail(ApiKeyMailer, :rotated).with hash_including(params: {api_key:})
          end
        end

        context "with free organization" do
          it "expires the API key with current time" do
            expect { service_result }.to change(api_key, :expires_at).to(Time.current)
          end

          it "creates a new API key for organization" do
            expect { service_result }.to change(ApiKey.unscoped, :count).by(1)

            expect(service_result.api_key)
              .to be_persisted.and have_attributes(organization:, name:)
          end

          it "sends an API key rotated email" do
            expect { service_result }
              .to have_enqueued_mail(ApiKeyMailer, :rotated).with hash_including(params: {api_key:})
          end
        end
      end
    end

    context "when API key is missing" do
      let(:api_key) { nil }
      let(:expires_at) { double }

      it "does not creates a new API key for organization" do
        expect { service_result }.not_to change(ApiKey, :count)
      end

      it "does not send an API key rotated email" do
        expect { service_result }.not_to have_enqueued_mail(ApiKeyMailer, :rotated)
      end

      it "returns an error" do
        expect(service_result).not_to be_success
        expect(service_result.error).to be_a(BaseService::NotFoundFailure)
        expect(service_result.error.error_code).to eq("api_key_not_found")
      end

      it "does not produce a security log" do
        service_result

        expect(security_logger).not_to have_received(:produce)
      end
    end
  end
end
